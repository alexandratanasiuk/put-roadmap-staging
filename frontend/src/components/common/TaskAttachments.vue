<template>
  <div class="attach-block">
    <div class="attach-head">
      <span>Вложения</span>
      <span class="attach-count">{{ readyCount }}</span>
      <button type="button" class="attach-add" :disabled="fileUploading || !canUpload" @click="openFilePicker">
        {{ fileUploading ? 'Загрузка…' : '+ Файл' }}
      </button>
    </div>
    <p v-if="fileError" class="attach-error">{{ fileError }}</p>
    <div v-if="fileUploading" class="attach-loader" role="status">
      <div class="attach-loader-row">
        <span class="attach-spinner" aria-hidden="true"></span>
        <span class="attach-loader-text">{{ uploadLabel }}</span>
        <span class="attach-loader-pct">{{ uploadPhase === 'send' ? `${uploadPercent}%` : '…' }}</span>
      </div>
      <div class="attach-loader-track">
        <div
          class="attach-loader-bar"
          :class="{ 'is-indeterminate': uploadPhase !== 'send' }"
          :style="uploadPhase === 'send' ? { width: uploadPercent + '%' } : null"
        ></div>
      </div>
    </div>
    <p v-if="!attachments.length && !fileUploading && !listLoading" class="attach-empty">Нет вложений</p>
    <p v-else-if="listLoading && !attachments.length" class="attach-empty">Загрузка списка…</p>
    <ul v-else class="attach-list">
      <li
        v-for="file in attachments"
        :key="file.id"
        class="attach-item"
        :class="{ 'is-pending': file.pending, 'is-failed': file.failed }"
      >
        <button
          type="button"
          class="attach-name"
          :disabled="file.pending || file.failed"
          @click="downloadAttachment(file)"
        >
          {{ file.fileName }}
          <span v-if="file.pending" class="attach-size">{{ file.pendingLabel || 'загрузка…' }}</span>
          <span v-else-if="file.failed" class="attach-size attach-fail">ошибка</span>
          <span v-else class="attach-size">{{ formatBytes(file.byteSize) }}</span>
        </button>
        <button
          v-if="!file.pending"
          type="button"
          class="attach-remove"
          aria-label="Удалить вложение"
          @click="removeAttachment(file)"
        >×</button>
        <span v-else class="attach-pending-spin" aria-hidden="true"></span>
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
const listLoading = ref(false)
const fileError = ref('')
const uploadTotal = ref(0)
const uploadDone = ref(0)
const uploadName = ref('')
const uploadPercent = ref(0)
const uploadPhase = ref('send')
const uploadProgressMap = ref({})
const FILE_LIMIT = 50 * 1024 * 1024
const UPLOAD_CONCURRENCY = 1

const readyCount = computed(() => attachments.value.filter((item) => item?.id && !item.pending && !item.failed).length)

const uploadLabel = computed(() => {
  const total = uploadTotal.value
  const done = uploadDone.value
  const name = uploadName.value || 'файл'
  if (total > 1) {
    if (uploadPhase.value === 'read') return `${done} из ${total} · чтение «${name}»…`
    if (uploadPhase.value === 'save') return `${done} из ${total} готово, сохранение…`
    return `${done} из ${total} готово · ${name}`
  }
  if (uploadPhase.value === 'read') return `чтение «${name}»…`
  if (uploadPhase.value === 'save') return `сохранение «${name}»…`
  return name
})

const refreshOverallProgress = () => {
  const total = uploadTotal.value
  if (!total) {
    uploadPercent.value = 0
    return
  }
  const values = Object.values(uploadProgressMap.value)
  const sum = values.reduce((acc, value) => acc + (Number(value) || 0), 0)
  uploadPercent.value = Math.min(100, Math.round(sum / total))
  const reading = attachments.value.some((item) => item.pending && item.pendingLabel === 'чтение…')
  const saving = attachments.value.some((item) => item.pending && item.pendingLabel === 'сохранение…')
  uploadPhase.value = reading ? 'read' : saving ? 'save' : 'send'
}

const canUpload = computed(() => Boolean(props.blockId && props.taskId))

const filesPath = () => {
  if (!props.blockId || !props.taskId) return ''
  return `${API_URL}/blocks/${props.blockId}/tasks/${props.taskId}/files`
}

const loadAttachments = async () => {
  const path = filesPath()
  const keepPending = attachments.value.filter((item) => item.pending)
  attachments.value = keepPending
  if (!path) return
  listLoading.value = true
  try {
    const response = await axios.get(path, { timeout: 15000 })
    const remote = Array.isArray(response.data) ? response.data : []
    const remoteIds = new Set(remote.map((item) => String(item.id)))
    const pending = keepPending.filter((item) => !remoteIds.has(String(item.id)))
    attachments.value = [...remote, ...pending]
  } catch (error) {
    fileError.value = error?.response?.data?.error || 'Не удалось загрузить вложения'
  } finally {
    listLoading.value = false
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

const replacePending = (pendingId, next) => {
  attachments.value = attachments.value.map((item) => (String(item.id) === String(pendingId) ? next : item))
}

const removePending = (pendingId) => {
  attachments.value = attachments.value.filter((item) => String(item.id) !== String(pendingId))
}

const timeoutForSize = (size) => {
  const mb = Math.max(1, Number(size) / (1024 * 1024))
  return Math.min(120000, Math.max(30000, Math.round(mb * 8000)))
}

const authHeader = () => {
  const value = axios.defaults.headers?.common?.Authorization
  return typeof value === 'string' ? value : ''
}

const setPendingProgress = (pendingId, pct, label) => {
  uploadProgressMap.value = {
    ...uploadProgressMap.value,
    [pendingId]: pct
  }
  if (label) {
    const prev = attachments.value.find((item) => String(item.id) === String(pendingId))
    replacePending(pendingId, {
      id: pendingId,
      fileName: prev?.fileName || 'файл',
      byteSize: prev?.byteSize || 0,
      pending: true,
      pendingLabel: label
    })
  }
  refreshOverallProgress()
}

const uploadOneFile = (path, file, pendingId) => new Promise((resolve, reject) => {
  uploadName.value = file.name || 'файл'
  setPendingProgress(pendingId, 0, 'отправка…')
  const xhr = new XMLHttpRequest()
  xhr.open('POST', path)
  xhr.timeout = timeoutForSize(file.size)
  xhr.setRequestHeader('Content-Type', 'application/octet-stream')
  xhr.setRequestHeader('X-File-Name', encodeURIComponent(file.name || 'file'))
  xhr.setRequestHeader('X-File-Mime', file.type || 'application/octet-stream')
  const auth = authHeader()
  if (auth) xhr.setRequestHeader('Authorization', auth)
  xhr.upload.onprogress = (event) => {
    const total = event.lengthComputable ? event.total : file.size
    if (!total) return
    const pct = Math.min(99, Math.round((event.loaded / total) * 100))
    if (event.loaded >= total) setPendingProgress(pendingId, 99, 'сохранение…')
    else setPendingProgress(pendingId, pct, 'отправка…')
  }
  xhr.onload = () => {
    let data = null
    try { data = JSON.parse(xhr.responseText || '{}') } catch { data = null }
    if (xhr.status >= 200 && xhr.status < 300 && data?.id) {
      resolve(data)
      return
    }
    reject(new Error(data?.error || `ошибка ${xhr.status || 'сети'}`))
  }
  xhr.onerror = () => reject(new Error('ошибка сети'))
  xhr.ontimeout = () => reject(new Error('сервер не ответил'))
  xhr.onabort = () => reject(new Error('загрузка прервана'))
  xhr.send(file)
})

const runWithConcurrency = async (items, limit, worker) => {
  const queue = items.map((item, index) => ({ item, index }))
  const results = new Array(items.length)
  const workers = Array.from({ length: Math.min(limit, queue.length) || 0 }, async () => {
    while (queue.length) {
      const next = queue.shift()
      if (!next) break
      results[next.index] = await worker(next.item, next.index)
    }
  })
  await Promise.all(workers)
  return results
}

const uploadFiles = async (fileList) => {
  const path = filesPath()
  if (!path) return []
  const files = [...(fileList || [])].filter((file) => file && file.size)
  if (!files.length) return []
  fileError.value = ''
  fileUploading.value = true
  uploadTotal.value = files.length
  uploadDone.value = 0
  uploadPercent.value = 0
  uploadPhase.value = 'send'
  uploadProgressMap.value = {}
  const uploaded = []
  const errors = []

  const jobs = []
  files.forEach((file, index) => {
    if (file.size > FILE_LIMIT) {
      errors.push(`«${file.name}» больше 50 МБ`)
      uploadDone.value += 1
      return
    }
    const pendingId = `pending-${Date.now()}-${index}`
    attachments.value = [
      ...attachments.value,
      {
        id: pendingId,
        fileName: file.name || 'файл',
        byteSize: file.size,
        pending: true,
        pendingLabel: 'отправка…'
      }
    ]
    uploadProgressMap.value = { ...uploadProgressMap.value, [pendingId]: 0 }
    jobs.push({ file, pendingId })
  })

  refreshOverallProgress()

  await runWithConcurrency(jobs, UPLOAD_CONCURRENCY, async (job) => {
    const { file, pendingId } = job
    try {
      const data = await uploadOneFile(path, file, pendingId)
      if (data?.id) {
        replacePending(pendingId, data)
        uploaded.push(data)
        uploadProgressMap.value = { ...uploadProgressMap.value, [pendingId]: 100 }
      } else {
        removePending(pendingId)
        errors.push(`«${file.name}»: сервер не вернул файл`)
        uploadProgressMap.value = { ...uploadProgressMap.value, [pendingId]: 100 }
      }
    } catch (error) {
      removePending(pendingId)
      const message = error?.response?.data?.error || error?.message || 'ошибка сети'
      errors.push(`«${file.name}»: ${message}`)
      uploadProgressMap.value = { ...uploadProgressMap.value, [pendingId]: 100 }
    } finally {
      uploadDone.value += 1
      refreshOverallProgress()
    }
  })

  if (errors.length) fileError.value = errors.join('; ')
  fileUploading.value = false
  uploadName.value = ''
  uploadPercent.value = 0
  uploadPhase.value = 'send'
  uploadProgressMap.value = {}
  return uploaded
}

const onFileInput = async (event) => {
  const input = event.target
  await uploadFiles(input?.files)
  if (input) input.value = ''
}

const downloadAttachment = async (file) => {
  const path = filesPath()
  if (!path || !file?.id || file.pending || file.failed) return
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
  if (file.pending) {
    removePending(file.id)
    return
  }
  if (file.failed) {
    removePending(file.id)
    return
  }
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
.attach-loader {
  margin-top: 8px;
}
.attach-loader-row {
  display: flex;
  align-items: center;
  gap: 8px;
  min-width: 0;
}
.attach-spinner,
.attach-pending-spin {
  width: 14px;
  height: 14px;
  flex: 0 0 auto;
  border: 2px solid #bfdbfe;
  border-top-color: #1d4ed8;
  border-radius: 50%;
  animation: attach-spin 0.7s linear infinite;
}
.attach-loader-text {
  flex: 1;
  min-width: 0;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
  font-size: 0.82rem;
  font-weight: 500;
  color: #334155;
}
.attach-loader-pct {
  flex: 0 0 auto;
  font-size: 0.75rem;
  color: #64748b;
}
.attach-loader-track {
  margin-top: 6px;
  height: 4px;
  border-radius: 999px;
  background: #e2e8f0;
  overflow: hidden;
}
.attach-loader-bar {
  height: 100%;
  border-radius: inherit;
  background: #2563eb;
  transition: width 0.15s linear;
}
.attach-loader-bar.is-indeterminate {
  width: 40%;
  animation: attach-bar 1s ease-in-out infinite;
}
@keyframes attach-spin {
  to { transform: rotate(360deg); }
}
@keyframes attach-bar {
  0% { transform: translateX(-120%); }
  100% { transform: translateX(320%); }
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
.attach-item.is-pending .attach-name {
  color: #64748b;
  cursor: default;
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
.attach-name:disabled {
  cursor: default;
}
.attach-size {
  margin-left: 8px;
  color: #94a3b8;
  font-size: 0.75rem;
}
.attach-fail {
  color: #b91c1c;
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
