<template>
  <div class="attach-block">
    <div class="attach-head">
      <span>Вложения</span>
      <span class="attach-count">{{ attachments.length }}</span>
      <button type="button" class="attach-add" :disabled="fileUploading || !canUpload" @click="openFilePicker">
        {{ fileUploading ? 'Загрузка…' : '+ Файл' }}
      </button>
    </div>
    <p v-if="fileError" class="attach-error">{{ fileError }}</p>
    <p v-if="!attachments.length && !fileUploading" class="attach-empty">Нет вложений</p>
    <ul v-else class="attach-list">
      <li v-for="file in attachments" :key="file.id" class="attach-item">
        <button type="button" class="attach-name" @click="downloadAttachment(file)">
          {{ file.fileName }}
          <span class="attach-size">{{ formatBytes(file.byteSize) }}</span>
        </button>
        <button type="button" class="attach-remove" aria-label="Удалить вложение" @click="removeAttachment(file)">×</button>
      </li>
    </ul>
    <input ref="fileInputRef" type="file" class="file-input" multiple @change="onFileInput">
  </div>
</template>

<script setup>
import { computed, ref, watch } from 'vue'
import axios from 'axios'
import { useAuth } from '@/composables/useAuth'

const props = defineProps({
  blockId: { type: [String, Number], default: '' },
  taskId: { type: [String, Number], default: '' }
})

const { API_URL } = useAuth()
const attachments = ref([])
const fileInputRef = ref(null)
const fileUploading = ref(false)
const fileError = ref('')
const FILE_LIMIT = 50 * 1024 * 1024

const canUpload = computed(() => Boolean(props.blockId && props.taskId))

const filesPath = () => {
  if (!props.blockId || !props.taskId) return ''
  return `${API_URL}/blocks/${props.blockId}/tasks/${props.taskId}/files`
}

const loadAttachments = async () => {
  const path = filesPath()
  attachments.value = []
  if (!path) return
  try {
    const response = await axios.get(path, { timeout: 15000 })
    attachments.value = Array.isArray(response.data) ? response.data : []
  } catch (error) {
    fileError.value = error?.response?.data?.error || 'Не удалось загрузить вложения'
  }
}

watch(
  () => [props.blockId, props.taskId],
  () => {
    fileError.value = ''
    loadAttachments()
  },
  { immediate: true }
)

const formatBytes = (size) => {
  const value = Number(size) || 0
  if (value < 1024) return `${value} Б`
  if (value < 1024 * 1024) return `${Math.round(value / 1024)} КБ`
  return `${(value / (1024 * 1024)).toFixed(1)} МБ`
}

const openFilePicker = () => {
  fileInputRef.value?.click()
}

const uploadFiles = async (fileList) => {
  const path = filesPath()
  if (!path) return
  const files = [...(fileList || [])]
  if (!files.length) return
  fileError.value = ''
  fileUploading.value = true
  const uploaded = []
  try {
    for (const file of files) {
      if (file.size > FILE_LIMIT) {
        fileError.value = `«${file.name}» больше 50 МБ`
        continue
      }
      if (!file.size) continue
      const response = await axios.post(path, file, {
        timeout: 180000,
        headers: {
          'Content-Type': 'application/octet-stream',
          'X-File-Name': encodeURIComponent(file.name || 'file'),
          'X-File-Mime': file.type || 'application/octet-stream'
        },
        transformRequest: [(data) => data]
      })
      if (response?.data?.id) uploaded.push(response.data)
    }
    await loadAttachments()
  } catch (error) {
    fileError.value = error?.response?.data?.error || 'Не удалось загрузить файл'
  } finally {
    fileUploading.value = false
  }
  return uploaded
}

const onFileInput = async (event) => {
  const input = event.target
  await uploadFiles(input?.files)
  if (input) input.value = ''
}

const downloadAttachment = async (file) => {
  const path = filesPath()
  if (!path || !file?.id) return
  try {
    const response = await axios.get(`${path}/${file.id}`, { responseType: 'blob', timeout: 180000 })
    const url = URL.createObjectURL(response.data)
    const link = document.createElement('a')
    link.href = url
    link.download = file.fileName || 'file'
    link.click()
    URL.revokeObjectURL(url)
  } catch (error) {
    fileError.value = error?.response?.data?.error || 'Не удалось скачать файл'
  }
}

const removeAttachment = async (file) => {
  const path = filesPath()
  if (!path || !file?.id) return
  try {
    await axios.delete(`${path}/${file.id}`)
    attachments.value = attachments.value.filter((item) => item.id !== file.id)
  } catch (error) {
    fileError.value = error?.response?.data?.error || 'Не удалось удалить файл'
  }
}

defineExpose({ uploadFiles, openFilePicker })
</script>

<style scoped>
.attach-block {
  margin-top: 4px;
  padding: 10px 12px;
  border: 1px solid #cbd5e1;
  border-radius: 8px;
  background: #ffffff;
}
.attach-head {
  display: flex;
  align-items: center;
  gap: 8px;
  font-size: 0.9rem;
  font-weight: 600;
  color: #0f172a;
}
.attach-count {
  min-width: 20px;
  height: 20px;
  padding: 0 6px;
  border-radius: 999px;
  background: #e2e8f0;
  color: #334155;
  font-size: 0.75rem;
  display: inline-flex;
  align-items: center;
  justify-content: center;
}
.attach-add {
  margin-left: auto;
  border: 1px solid #bfdbfe;
  background: #eff6ff;
  color: #1d4ed8;
  border-radius: 7px;
  font-weight: 600;
  font-size: 0.8rem;
  padding: 4px 8px;
  cursor: pointer;
  font-family: inherit;
}
.attach-add:disabled {
  color: #94a3b8;
  border-color: #e2e8f0;
  background: #f8fafc;
  cursor: default;
}
.attach-empty,
.attach-error {
  margin: 8px 0 0;
  font-size: 0.85rem;
  color: #64748b;
}
.attach-error {
  color: #b91c1c;
}
.attach-list {
  list-style: none;
  margin: 8px 0 0;
  padding: 0;
  display: flex;
  flex-direction: column;
  gap: 4px;
}
.attach-item {
  display: flex;
  align-items: center;
  gap: 8px;
}
.attach-name {
  flex: 1;
  min-width: 0;
  border: none;
  background: transparent;
  text-align: left;
  color: #1d4ed8;
  font-size: 0.88rem;
  cursor: pointer;
  font-family: inherit;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}
.attach-size {
  margin-left: 8px;
  color: #94a3b8;
  font-size: 0.75rem;
}
.attach-remove {
  width: 24px;
  height: 24px;
  border: none;
  border-radius: 6px;
  background: transparent;
  color: #64748b;
  cursor: pointer;
}
.attach-remove:hover {
  background: #fee2e2;
  color: #b91c1c;
}
.file-input {
  display: none;
}
</style>
