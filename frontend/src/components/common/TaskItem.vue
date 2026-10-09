<template>
  <div
    class="task-item"
    :class="{
      'task-done': task.status === 'done',
      'is-in-progress': task.status === 'progress',
      'drag-over': dragOver,
      'dragging': dragging,
      'task-readonly': readOnly
    }"
    :draggable="!readOnly && !task.isEditing"
    @dragstart="onDragStart"
    @dragend="onDragEnd"
    @dragover="onDragOver"
    @drop="onDrop"
    @dragenter="onDragEnter"
    @dragleave="onDragLeave"
  >
    <Tooltip :label="readOnly ? 'Только просмотр' : getStatusTitle(task.status)">
      <button
        type="button"
        class="task-status"
        :class="[`task-status_${normalizedStatus}`, { 'is-disabled': readOnly }]"
        :draggable="!readOnly && !task.isEditing"
        @dragstart.stop="onDragStart"
        @dragend.stop="onDragEnd"
        @click.stop="cycleStatus"
        :aria-label="getStatusTitle(task.status)"
      ></button>
    </Tooltip>

    <div class="task-content">
      <div v-if="task.isEditing" class="task-edit-mode">
        <textarea
          ref="editInputRef"
          v-model="task.editValue"
          @keyup.enter="saveEdit"
          @keyup.esc="cancelEdit"
          @blur="onEditBlur"
          class="task-edit-input"
          rows="2"
        ></textarea>
      </div>
      <Tooltip v-else :label="task.title" fill only-truncated>
        <div
          class="task-title"
          :class="{ 'is-readonly': readOnly }"
          @click.stop="onTaskTitleClick"
        >
          {{ task.title }}
        </div>
      </Tooltip>
    </div>

    <div v-if="!readOnly && !task.isEditing" class="task-actions">
      <Tooltip v-if="hasLink()" label="Открыть ссылку">
        <button
          class="task-link-btn"
          type="button"
          aria-label="Открыть ссылку задачи"
          @click.stop="openTaskLink"
          @dragstart.stop.prevent
        >
          <img class="task-link-icon" :src="linkIcon" alt="" />
        </button>
      </Tooltip>
    </div>
  </div>
</template>

<script setup>
import { computed, ref, watch, nextTick } from 'vue'
import linkIcon from '@/assets/link-icon.png'
import Tooltip from './Tooltip.vue'

// Входные данные одной строки задачи + флаги DnD/режима просмотра.
const props = defineProps({
  task: { type: Object, required: true },
  block: { type: Object, required: true },
  dragOver: { type: Boolean, default: false },
  dragging: { type: Boolean, default: false },
  readOnly: { type: Boolean, default: false }
})

// События, которые строка задачи поднимает в родителя (изменение, редактирование, drag&drop).
const emit = defineEmits([
  'cycle-status',
  'start-edit',
  'open-card',
  'save-edit',
  'cancel-edit',
  'delete',
  'drag-start',
  'drag-end',
  'drag-over',
  'drop',
  'drag-enter',
  'drag-leave'
])

const normalizedStatus = computed(() => {
  if (props.task?.status === 'done') return 'done'
  if (props.task?.status === 'progress') return 'progress'
  return 'todo'
})

const getStatusTitle = (status) => {
  switch(status) {
    case 'done': return 'Выполнено'
    case 'progress': return 'В работе'
    default: return 'Не начато'
  }
}

const normalizeLinkUrl = (raw) => {
  if (!raw || typeof raw !== 'string') return ''
  const trimmed = raw.trim()
  if (!trimmed) return ''
  if (/^https?:\/\//i.test(trimmed)) return trimmed
  return `https://${trimmed}`
}

// Наличие ссылки управляет видимостью кнопки link.
const hasLink = () => Boolean(normalizeLinkUrl(props.task?.linkUrl || ''))

// Ref textarea и "окно стабилизации" после открытия inline-редактирования.
const editInputRef = ref(null)
const editOpenedAt = ref(0)
const EDIT_REFOCUS_WINDOW_MS = 500

// При входе в режим редактирования ставим фокус в конец текста.
watch(
  () => props.task?.isEditing,
  async (isEditing) => {
    if (!isEditing) return
    editOpenedAt.value = performance.now()
    await nextTick()
    const input = editInputRef.value
    if (!input) return
    input.focus({ preventScroll: true })
    const valueLength = typeof props.task?.editValue === 'string' ? props.task.editValue.length : 0
    input.setSelectionRange(valueLength, valueLength)
  }
)

// Открывает ссылку задачи в новой вкладке.
const openTaskLink = () => {
  const url = normalizeLinkUrl(props.task?.linkUrl || '')
  if (!url) return
  window.open(url, '_blank', 'noopener,noreferrer')
}

// Обработчики взаимодействий строки задачи.
const cycleStatus = (event) => {
  if (props.readOnly) return
  emit('cycle-status', event)
}

// Клик по названию открывает карточку задачи, а не inline-редактор.
const openCard = () => {
  if (props.readOnly) return
  emit('open-card')
}

const onTaskTitleClick = () => {
  openCard()
}

const saveEdit = (event) => {
  emit('save-edit', event)
}

const onEditBlur = (event) => {
  emit('save-edit', event)
  // Сразу после открытия редактора возможен ложный blur:
  // кратко рефокусируем поле, пока не прошел guard-интервал.
  nextTick(() => {
    requestAnimationFrame(() => {
      if (!props.task.isEditing) return
      const elapsed = performance.now() - editOpenedAt.value
      if (elapsed > EDIT_REFOCUS_WINDOW_MS) return
      const input = editInputRef.value
      if (!input || document.activeElement === input) return
      input.focus({ preventScroll: true })
    })
  })
}

const cancelEdit = () => {
  emit('cancel-edit')
}

// Drag старт блокируется в режиме read-only.
const onDragStart = (event) => {
  if (props.readOnly) {
    event.preventDefault()
    return
  }
  emit('drag-start', event)
}

const onDragEnd = () => {
  emit('drag-end')
}

const onDragOver = (event) => {
  emit('drag-over', event)
}

const onDrop = (event) => {
  emit('drop', event)
}

const onDragEnter = () => {
  emit('drag-enter')
}

const onDragLeave = (event) => {
  emit('drag-leave', event)
}
</script>

<style scoped>
.task-item {
  display: flex;
  flex-wrap: nowrap;
  align-items: center;
  gap: 6px;
  padding: 3px 0;
  cursor: grab;
  user-select: none;
  min-width: 0;
}
.task-item:active { cursor: grabbing; }
.task-item.task-readonly { cursor: default; }
.task-item.dragging {
  opacity: 0.5;
}
.task-item.drag-over {
  background: rgba(59, 130, 246, 0.08);
  box-shadow: inset 0 0 0 1px rgba(59, 130, 246, 0.28);
  border-radius: 6px;
}
.task-status {
  flex-shrink: 0;
  box-sizing: border-box;
  display: inline-flex;
  align-items: center;
  justify-content: center;
  width: 16px;
  height: 16px;
  min-width: 16px;
  margin: 0;
  padding: 0;
  border: 2px solid #94a3b8;
  border-radius: 50%;
  background: transparent;
  appearance: none;
  cursor: grab;
}
.task-status:active { cursor: grabbing; }
.task-status.is-disabled { cursor: default; }
.task-status_progress {
  border-color: #3b82f6;
  background: #3b82f6;
  box-shadow: inset 0 0 0 3px #fff;
}
.task-status_done {
  border-color: #22c55e;
  background: #22c55e;
  position: relative;
}
.task-status_done::after {
  content: '';
  position: absolute;
  left: 3px;
  top: 1px;
  width: 5px;
  height: 8px;
  border: solid #fff;
  border-width: 0 1.6px 1.6px 0;
  transform: rotate(45deg);
}
.task-content {
  flex: 1;
  min-width: 0;
}
.task-edit-mode {
  width: 100%;
  max-width: 100%;
  overflow: hidden;
}
.task-title {
  display: block;
  width: 100%;
  min-width: 0;
  font-size: 0.88rem;
  line-height: 1.3;
  color: #0f172a;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
  cursor: pointer;
}
.task-title:hover { color: #1d4ed8; }
.task-actions {
  display: flex;
  align-items: center;
  flex-shrink: 0;
}
.task-link-btn {
  width: 20px;
  height: 20px;
  border: none;
  background: transparent;
  cursor: pointer;
  border-radius: 4px;
  display: flex;
  align-items: center;
  justify-content: center;
  padding: 0;
}
.task-link-btn:hover {
  background: rgba(37, 99, 235, 0.08);
}
.task-link-icon {
  width: 16px;
  height: 16px;
  display: block;
}
.task-edit-input {
  width: 100%;
  box-sizing: border-box;
  padding: 4px 6px;
  border: 1px solid #3b82f6;
  border-radius: 6px;
  font-size: 0.75rem;
  outline: none;
  background: white;
  resize: none;
  min-height: 32px;
  height: 32px;
  font-family: inherit;
}
</style>