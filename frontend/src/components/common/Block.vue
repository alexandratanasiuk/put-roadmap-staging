<template>
  <div
    class="block"
    :style="style"
    :class="{ completed: block.completed, editing: block.editing }"
    :data-block-id="block.id"
  >
    <div
      class="block-header"
      :class="{ 'header-readonly': readOnly }"
      :draggable="!readOnly"
      @dragstart="onBlockDragStart"
      @dragend="onBlockDragEnd"
    >
      <Tooltip :label="block.title" fill>
        <button
          type="button"
          class="block-title"
          @click.stop="onTitleClick"
        >
          {{ block.title }}
        </button>
      </Tooltip>

      <div v-if="dateRangeText || block.isOverdue" class="block-header-meta">
        <Tooltip v-if="block.isOverdue" :label="overdueTitle">
          <span
            class="block-overdue"
            aria-label="Просрочен"
          >
            <svg viewBox="0 0 20 20" width="16" height="16" aria-hidden="true">
              <path
                d="M10 3.2 17.5 16H2.5L10 3.2Z"
                fill="none"
                stroke="#dc2626"
                stroke-width="1.6"
                stroke-linejoin="round"
              />
              <path d="M10 8v4.2" stroke="#dc2626" stroke-width="1.6" stroke-linecap="round" />
              <circle cx="10" cy="14.2" r="0.8" fill="#dc2626" />
            </svg>
          </span>
        </Tooltip>

        <button
          v-if="!block.editingDate && dateRangeText"
          type="button"
          class="block-date"
          :class="{ 'is-readonly': readOnly }"
          @click.stop="onReleaseClick"
        >
          <svg viewBox="0 0 16 16" width="14" height="14" aria-hidden="true">
            <rect x="2" y="3.5" width="12" height="10.5" rx="1.5" fill="none" stroke="currentColor" stroke-width="1.3" />
            <path d="M2 6.5h12" stroke="currentColor" stroke-width="1.3" />
            <path d="M5.5 2v3M10.5 2v3" stroke="currentColor" stroke-width="1.3" stroke-linecap="round" />
          </svg>
          <span>{{ dateRangeText }}</span>
        </button>
        <div
          v-else-if="block.editingDate"
          class="block-date-editor"
          @click.stop
          @mousedown.stop
          @focusout="onDateEditorFocusOut"
        >
          <Tooltip label="Начало этапа">
          <input
            ref="startDateInputRef"
            type="date"
            v-model="editStartDate"
            aria-label="Начало этапа"
            @change="commitDateEdit('startDate', true)"
            @keydown.enter.prevent="commitDateEdit('startDate')"
            @keydown.esc.prevent="$emit('cancel-edit-date')"
          />
          </Tooltip>
          <span class="block-date-sep">—</span>
          <Tooltip label="Конец этапа">
          <input
            ref="endDateInputRef"
            type="date"
            v-model="editEndDate"
            aria-label="Конец этапа"
            @change="commitDateEdit('releaseDate', true)"
            @keydown.enter.prevent="commitDateEdit('releaseDate')"
            @keydown.esc.prevent="$emit('cancel-edit-date')"
          />
          </Tooltip>
        </div>
      </div>
    </div>

    <div class="block-tasks">
      <div class="tasks-header">
        <span class="tasks-title">Элементы</span>
        <Tooltip v-if="!readOnly" label="Добавить задачу">
        <button
          class="add-task-btn"
          type="button"
          @click.stop="$emit('add-task')"
          aria-label="Добавить задачу"
        >
          <svg viewBox="0 0 24 24" width="20" height="20" aria-hidden="true">
            <circle cx="12" cy="12" r="9" fill="none" stroke="currentColor" stroke-width="1.6" />
            <path d="M12 8v8M8 12h8" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" />
          </svg>
        </button>
        </Tooltip>
      </div>

      <div
        class="tasks-list"
        :class="{ 'is-empty': !sortedTasks.length }"
        @dragover.prevent
        @drop.prevent="onDropTask($event, null)"
      >
        <TaskItem
          v-for="task in sortedTasks"
          :key="task.id"
          :task="task"
          :block="block"
          :read-only="readOnly"
          :drag-over="dragOverTask?.id === task.id"
          :dragging="draggedTask?.id === task.id"
          @cycle-status="(e) => $emit('cycle-task-status', task, e)"
          @open-card="openTaskCard(task)"
          @start-edit="() => $emit('start-task-edit', task)"
          @save-edit="(e) => $emit('save-task-edit', task, e)"
          @cancel-edit="() => $emit('cancel-task-edit', task)"
          @delete="() => $emit('delete-task', task)"
          @drag-start="(e) => $emit('task-drag-start', e, block, task)"
          @drag-end="$emit('task-drag-end')"
          @drag-over="(e) => $emit('task-drag-over', e)"
          @drop="(e) => $emit('task-drop', e, block, task)"
          @drag-enter="() => $emit('task-drag-enter', block, task)"
          @drag-leave="(e) => $emit('task-drag-leave', e)"
        />
        <span v-if="!sortedTasks.length" class="empty-text">Нет элементов</span>
      </div>
    </div>

    <div class="block-progress">
      <div class="progress-header">
        <span class="progress-label">Прогресс этапа</span>
        <span class="progress-value">{{ progressLabel }}</span>
      </div>
      <div class="progress-bar-container">
        <div
          class="progress-bar-fill"
          :style="{ width: taskProgress + '%' }"
        ></div>
      </div>
    </div>

    <div class="block-effort-summary">
      <span class="effort-label">Трудозатраты:</span>
      <span class="effort-value" :class="{ 'is-over': isEffortOver }">
        {{ totalTasksEffort }}&nbsp;/&nbsp;{{ block.effort || 0 }}&nbsp;ч
      </span>
    </div>
  </div>
</template>

<script setup>
import { computed, inject, unref, ref, watch, nextTick } from 'vue'
import TaskItem from './TaskItem.vue'
import Tooltip from './Tooltip.vue'
import { useBlocks } from '@/composables/useBlocks'

const props = defineProps({
  block: { type: Object, required: true },
  style: { type: Object, default: () => ({}) },
  dragOverTask: { type: Object, default: null },
  draggedTask: { type: Object, default: null }
})

const emit = defineEmits([
  'edit-block',
  'add-task',
  'cycle-task-status',
  'start-task-edit',
  'save-task-edit',
  'cancel-task-edit',
  'delete-task',
  'task-drag-start',
  'task-drag-end',
  'task-drag-over',
  'task-drop',
  'task-drag-enter',
  'task-drag-leave',
  'open-task-card',
  'block-drag-start',
  'block-drag-end',
  'start-edit-date',
  'save-date',
  'cancel-edit-date'
])

const { getTaskProgress, getCompletedTasksCount } = useBlocks()

const readOnlyInjected = inject('readOnly', computed(() => false))
const readOnly = computed(() => Boolean(unref(readOnlyInjected)))
const startDateInputRef = ref(null)
const endDateInputRef = ref(null)
const editStartDate = ref('')
const editEndDate = ref('')

const toDateInputValue = (value) => {
  const raw = String(value || '').trim()
  if (/^\d{4}-\d{2}-\d{2}/.test(raw)) return raw.slice(0, 10)
  return ''
}

const commitDateEdit = (changedField, keepOpen = false) => {
  emit('save-date', {
    startDate: editStartDate.value,
    releaseDate: editEndDate.value,
    changedField,
    keepOpen
  })
}

const onDateEditorFocusOut = (event) => {
  const root = event.currentTarget
  if (root.contains(event.relatedTarget)) return
  requestAnimationFrame(() => {
    const active = document.activeElement
    if (active === startDateInputRef.value || active === endDateInputRef.value) return
    emit('cancel-edit-date')
  })
}

watch(
  () => props.block?.editingDate,
  async (isEditing) => {
    if (!isEditing) return
    editStartDate.value = toDateInputValue(props.block.startDate)
    editEndDate.value = toDateInputValue(props.block.releaseDate)
    await nextTick()
    startDateInputRef.value?.focus({ preventScroll: true })
  }
)

const onTitleClick = () => {
  emit('edit-block')
}

const onReleaseClick = () => {
  if (readOnly.value) return
  emit('start-edit-date')
}

const openTaskCard = (task) => {
  if (readOnly.value) return
  emit('open-task-card', task)
}

const sortedTasks = computed(() => {
  if (!props.block.tasks) return []
  return [...props.block.tasks].sort((a, b) => (a.order || 0) - (b.order || 0))
})

const taskProgress = computed(() => getTaskProgress(props.block))
const completedTasksCount = computed(() => getCompletedTasksCount(props.block))
const totalTasksEffort = computed(() => {
  if (!props.block.tasks || props.block.tasks.length === 0) return 0
  return props.block.tasks.reduce((sum, task) => sum + (task.effort || 0), 0)
})

const isEffortOver = computed(() => {
  const stageEffort = Number(props.block.effort || 0)
  if (!Number.isFinite(stageEffort) || stageEffort <= 0) return false
  return totalTasksEffort.value > stageEffort
})

const progressLabel = computed(() => {
  const total = Array.isArray(props.block.tasks) ? props.block.tasks.length : 0
  if (!total) return '0%'
  return `${taskProgress.value}% (${completedTasksCount.value}/${total})`
})

const formatDate = (dateStr) => {
  if (!dateStr) return ''
  const date = new Date(dateStr)
  if (Number.isNaN(date.getTime())) return ''
  const day = date.getDate().toString().padStart(2, '0')
  const month = (date.getMonth() + 1).toString().padStart(2, '0')
  const year = date.getFullYear()
  return `${day}.${month}.${year}`
}

const dateRangeText = computed(() => {
  const startText = formatDate(props.block.startDate)
  const endText = formatDate(props.block.releaseDate)
  if (!startText && !endText) return ''
  if (startText && endText) return `${startText} — ${endText}`
  if (startText) return `${startText} — …`
  return `… — ${endText}`
})

const overdueTitle = computed(() => {
  if (!props.block?.isOverdue) return 'Просрочен'
  const endText = formatDate(props.block.releaseDate)
  return endText ? `Просрочен (до ${endText})` : 'Просрочен'
})

const onDropTask = (event, targetTask) => {
  emit('task-drop', event, props.block, targetTask)
}

const onBlockDragStart = (event) => {
  if (readOnly.value) {
    event.preventDefault()
    return
  }
  if (event.target.closest('.block-date, .block-date-editor, .block-overdue')) {
    event.preventDefault()
    return
  }
  emit('block-drag-start', event, props.block)
}

const onBlockDragEnd = () => {
  emit('block-drag-end')
}
</script>

<style scoped>
.block {
  position: absolute;
  display: flex;
  flex-direction: column;
  gap: 8px;
  background: white;
  border: none;
  border-radius: 10px;
  padding: 12px;
  box-shadow: 0 1px 2px rgba(15, 23, 42, 0.04);
  transition: transform 0.2s ease, box-shadow 0.2s ease;
  z-index: 50;
  cursor: pointer;
  box-sizing: border-box;
  overflow: visible !important;
  font-family: Inter, system-ui, -apple-system, 'Segoe UI', Roboto, Arial, sans-serif;
  font-weight: 400;
}
.block:hover {
  transform: translateY(-2px);
  box-shadow:
    0 8px 24px rgba(0, 0, 0, 0.12),
    0 2px 8px rgba(0, 0, 0, 0.06);
  z-index: 21;
}
.block.completed {
  background: #90EE90 !important;
  border-color: #86efac;
}

.block-header {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  justify-content: space-between;
  gap: 6px 8px;
  padding: 8px;
  border-radius: 6px;
  background: rgba(255, 255, 255, 0.72);
  cursor: grab;
  user-select: none;
  min-width: 0;
}
.block-header:active { cursor: grabbing; }
.block-header.header-readonly,
.block-header.header-readonly:active {
  cursor: default;
}

.block-title {
  display: block;
  width: 100%;
  min-width: 0;
  margin: 0;
  padding: 0;
  border: none;
  background: none;
  text-align: left;
  font-family: Inter, system-ui, sans-serif;
  font-weight: 600;
  font-size: 0.95rem;
  line-height: 1.3;
  color: #0f172a;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
  cursor: pointer;
}
.block-title:hover {
  color: #1d4ed8;
}

.block-header-meta {
  display: flex;
  align-items: center;
  gap: 6px;
  margin-left: auto;
  flex: 0 1 auto;
  white-space: nowrap;
}
.block-overdue {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  width: 18px;
  height: 18px;
}
.block-date {
  display: inline-flex;
  align-items: center;
  gap: 4px;
  padding: 2px 4px;
  border: none;
  border-radius: 4px;
  background: none;
  color: #475569;
  font-size: 0.75rem;
  line-height: 1;
  cursor: pointer;
}
.block-date:hover {
  background: rgba(148, 163, 184, 0.16);
}
.block-date.is-readonly {
  cursor: default;
  pointer-events: none;
}
.block-date-editor {
  display: flex;
  align-items: center;
  gap: 4px;
  flex-wrap: wrap;
  max-width: 100%;
}
.block-date-sep {
  color: #94a3b8;
  font-size: 0.75rem;
  line-height: 1;
}
.block-date-editor input[type="date"] {
  width: 118px;
  max-width: 100%;
  box-sizing: border-box;
  padding: 4px 6px;
  border: 1px solid #cbd5e1;
  border-radius: 6px;
  font-size: 0.72rem;
  background: #fff;
  color: #334155;
  outline: none;
}
.block-date-editor input[type="date"]:focus {
  border-color: #3b82f6;
  box-shadow: 0 0 0 2px rgba(59, 130, 246, 0.12);
}

.block-tasks {
  display: flex;
  flex-direction: column;
  gap: 6px;
  padding: 8px;
  border-radius: 6px;
  background: rgba(255, 255, 255, 0.72);
  min-width: 0;
}
.tasks-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  min-height: 24px;
}
.tasks-title {
  font-size: 0.72rem;
  font-weight: 600;
  color: #64748b;
}
.add-task-btn {
  width: 24px;
  height: 24px;
  padding: 0;
  border: none;
  border-radius: 12px;
  background: none;
  color: #2563eb;
  cursor: pointer;
  display: inline-flex;
  align-items: center;
  justify-content: center;
}
.add-task-btn:hover {
  background: rgba(37, 99, 235, 0.1);
}
.tasks-list {
  display: flex;
  flex-direction: column;
  min-width: 0;
}
.tasks-list.is-empty {
  min-height: 28px;
  justify-content: center;
}
.empty-text {
  font-size: 0.75rem;
  color: #64748b;
}

.block-progress {
  display: flex;
  flex-direction: column;
  gap: 6px;
  min-width: 0;
}
.progress-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  gap: 8px;
  font-size: 0.72rem;
}
.progress-label {
  color: #64748b;
  font-weight: 600;
}
.progress-value {
  color: #0f172a;
  font-weight: 500;
  background: rgba(255, 255, 255, 0.8);
  padding: 2px 8px;
  border-radius: 8px;
}
.progress-bar-container {
  height: 6px;
  background: rgba(241, 245, 249, 0.9);
  border-radius: 3px;
  overflow: hidden;
}
.progress-bar-fill {
  height: 100%;
  background: #3b82f6;
  transition: width 0.3s ease;
  border-radius: 3px;
}

.block-effort-summary {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 8px;
  padding: 6px 8px;
  border-radius: 6px;
  background: rgba(255, 255, 255, 0.72);
  font-size: 0.72rem;
  flex-wrap: nowrap;
}
.effort-label {
  color: #64748b;
}
.effort-value {
  flex-shrink: 0;
  color: #0f172a;
  font-weight: 500;
  white-space: nowrap;
}
.effort-value.is-over {
  color: #dc2626;
}
</style>
