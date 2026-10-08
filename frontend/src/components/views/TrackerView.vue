<template>
  <div class="tracker-view">
    <div class="tracker-toolbar">
      <div class="tracker-filter">
        <label>Этап</label>
        <AppSelect
          v-model="stageFilterId"
          :options="stageFilterOptions"
          placeholder="Все этапы"
        />
      </div>
      <div class="tracker-toolbar-meta">
        {{ filteredItems.length }} {{ elementsWord(filteredItems.length) }}
      </div>
    </div>

    <div v-if="!blocks.length" class="tracker-empty">В проекте нет этапов</div>
    <div v-else class="tracker-board">
      <section
        v-for="column in columns"
        :key="column.id"
        class="tracker-column"
        :class="{
          [`is-${column.id}`]: true,
          'is-drop-target': dropStatus === column.id
        }"
        @dragover="onColumnDragOver($event, column.id)"
        @dragleave="onColumnDragLeave($event, column.id)"
        @drop="onColumnDrop($event, column.id)"
      >
        <header class="tracker-column-header">
          <span class="tracker-column-title">{{ column.title }}</span>
          <span class="tracker-column-count">{{ column.items.length }}</span>
        </header>
        <div class="tracker-column-body">
          <article
            v-for="item in column.items"
            :key="item.task.id"
            class="tracker-card"
            :class="{
              'is-dragging': draggedKey === itemKey(item),
              'is-readonly': readOnly
            }"
            role="button"
            :tabindex="readOnly ? -1 : 0"
            :draggable="!readOnly"
            @dragstart="onCardDragStart($event, item)"
            @dragend="onCardDragEnd"
            @dragover="onColumnDragOver($event, column.id)"
            @drop="onColumnDrop($event, column.id)"
            @click="onCardClick(item)"
            @keydown.enter.prevent="onCardClick(item)"
          >
            <div class="tracker-card-top">
              <Tooltip :label="readOnly ? 'Только просмотр' : getStatusTitle(item.task.status)">
                <button
                  type="button"
                  class="task-status"
                  :class="[`task-status_${normalizeStatus(item.task.status)}`, { 'is-disabled': readOnly }]"
                  :aria-label="getStatusTitle(item.task.status)"
                  @click.stop="onCycleStatus(item, $event)"
                ></button>
              </Tooltip>
              <Tooltip :label="item.task.title" fill>
                <div class="tracker-card-title">{{ item.task.title }}</div>
              </Tooltip>
              <Tooltip v-if="taskLink(item.task)" label="Открыть ссылку">
                <button
                  type="button"
                  class="tracker-card-link"
                  aria-label="Открыть ссылку"
                  @click.stop="openTaskLink(item.task)"
                  @dragstart.stop.prevent
                >
                  <img class="tracker-card-link-icon" :src="linkIcon" alt="">
                </button>
              </Tooltip>
            </div>
            <div class="tracker-card-stage">{{ item.block.title }}</div>
            <div v-if="cardMeta(item.task)" class="tracker-card-meta">
              {{ cardMeta(item.task) }}
            </div>
          </article>
          <div v-if="!column.items.length" class="tracker-column-empty">Нет элементов</div>
        </div>
      </section>
    </div>

    <TaskCardModal
      v-if="taskCardModalOpen"
      :block="taskCardBlock"
      :task="taskCardTask"
      @close="closeTaskCardModal"
      @save="saveTaskCardModal"
      @delete="deleteTaskCardModal"
    />
  </div>
</template>

<script setup>
import { computed, inject, ref, unref } from 'vue'
import { useBlocks } from '@/composables/useBlocks'
import { useTasks } from '@/composables/useTasks'
import { useNotification } from '@/composables/useNotification'
import AppSelect from '@/components/common/AppSelect.vue'
import TaskCardModal from '@/components/common/TaskCardModal.vue'
import Tooltip from '@/components/common/Tooltip.vue'
import linkIcon from '@/assets/link-icon.png'

const emit = defineEmits(['editBlock'])
void emit

const { blocks } = useBlocks()
const { getStatusTitle, cycleTaskStatus, setTaskStatus, saveTaskCard, deleteTask } = useTasks()
const { showNotificationMessage } = useNotification()

const readOnlyInjected = inject('readOnly', computed(() => false))
const readOnly = computed(() => Boolean(unref(readOnlyInjected)))

const COLUMN_DEFS = [
  { id: 'todo', title: 'Не начато' },
  { id: 'progress', title: 'В работе' },
  { id: 'done', title: 'Выполнено' }
]

const stageFilterId = ref('')
const draggedItem = ref(null)
const draggedKey = ref('')
const dropStatus = ref('')
const suppressClick = ref(false)
const taskCardModalOpen = ref(false)
const taskCardBlock = ref(null)
const taskCardTask = ref(null)

const normalizeStatus = (status) => {
  if (status === 'done' || status === 'progress') return status
  return 'todo'
}

const itemKey = (item) => `${item.block.id}::${item.task.id}`

const boardItems = computed(() => {
  const rows = []
  for (const block of blocks.value || []) {
    const tasks = Array.isArray(block?.tasks) ? block.tasks : []
    for (const task of tasks) {
      if (!task?.id) continue
      rows.push({ block, task })
    }
  }
  return rows
})

const stageFilterOptions = computed(() => {
  const options = [{ value: '', label: 'Все этапы' }]
  for (const block of blocks.value || []) {
    if (!block?.id) continue
    options.push({ value: String(block.id), label: block.title || 'Без названия' })
  }
  return options
})

const filteredItems = computed(() => {
  const filterId = String(stageFilterId.value || '')
  if (!filterId) return boardItems.value
  return boardItems.value.filter((item) => String(item.block.id) === filterId)
})

const columns = computed(() =>
  COLUMN_DEFS.map((column) => ({
    ...column,
    items: filteredItems.value.filter((item) => normalizeStatus(item.task.status) === column.id)
  }))
)

const elementsWord = (count) => {
  const n = Math.abs(Number(count) || 0) % 100
  const d = n % 10
  if (n > 10 && n < 20) return 'элементов'
  if (d === 1) return 'элемент'
  if (d >= 2 && d <= 4) return 'элемента'
  return 'элементов'
}

const normalizeLinkUrl = (raw) => {
  if (!raw || typeof raw !== 'string') return ''
  const trimmed = raw.trim()
  if (!trimmed) return ''
  if (/^https?:\/\//i.test(trimmed)) return trimmed
  return `https://${trimmed}`
}

const taskLink = (task) => normalizeLinkUrl(task?.linkUrl || '')

const openTaskLink = (task) => {
  const url = taskLink(task)
  if (!url) return
  window.open(url, '_blank', 'noopener,noreferrer')
}

const formatDate = (value) => {
  if (!value || typeof value !== 'string') return ''
  const trimmed = value.trim()
  if (!/^\d{4}-\d{2}-\d{2}$/.test(trimmed)) return ''
  const [, month, day] = trimmed.split('-')
  return `${day}.${month}`
}

const cardMeta = (task) => {
  const start = formatDate(task?.startDate)
  const end = formatDate(task?.releaseDate)
  const dates = start && end ? (start === end ? start : `${start} – ${end}`) : (start || end)
  const effortNum = Number(task?.effort) || 0
  const effort = effortNum > 0 ? `${effortNum} ч` : ''
  return [dates, effort].filter(Boolean).join(' · ')
}

const onCardDragStart = (event, item) => {
  if (readOnly.value) {
    event.preventDefault()
    return
  }
  const target = event.target
  if (target?.closest?.('input, textarea, a, .tracker-card-link, .task-status')) {
    event.preventDefault()
    return
  }
  draggedItem.value = item
  draggedKey.value = itemKey(item)
  suppressClick.value = true
  event.dataTransfer.effectAllowed = 'move'
  event.dataTransfer.setData('text/plain', item.task.id)
}

const onCardDragEnd = () => {
  draggedItem.value = null
  draggedKey.value = ''
  dropStatus.value = ''
  window.setTimeout(() => {
    suppressClick.value = false
  }, 0)
}

const onColumnDragOver = (event, status) => {
  if (!draggedItem.value) return
  event.preventDefault()
  event.dataTransfer.dropEffect = 'move'
  dropStatus.value = status
}

const onColumnDragLeave = (event, status) => {
  if (event.currentTarget.contains(event.relatedTarget)) return
  if (dropStatus.value === status) dropStatus.value = ''
}

const onColumnDrop = async (event, status) => {
  event.preventDefault()
  event.stopPropagation()
  const item = draggedItem.value
  dropStatus.value = ''
  if (!item) return
  const result = await setTaskStatus(item.block, item.task, status)
  if (result?.skipped) return
  if (result?.success) return
  if (result?.busy) return
  showNotificationMessage(result?.message || '❌ Ошибка обновления статуса', 'error')
}

const onCycleStatus = async (item, event) => {
  if (readOnly.value) return
  const result = await cycleTaskStatus(item.block, item.task, event)
  if (result?.success || result?.busy) return
  showNotificationMessage(result?.message || '❌ Ошибка обновления статуса', 'error')
}

const onCardClick = (item) => {
  if (suppressClick.value) return
  if (readOnly.value) return
  taskCardBlock.value = item.block
  taskCardTask.value = item.task
  taskCardModalOpen.value = true
}

const closeTaskCardModal = () => {
  taskCardModalOpen.value = false
  taskCardBlock.value = null
  taskCardTask.value = null
}

const saveTaskCardModal = async (patch) => {
  const block = taskCardBlock.value
  const task = taskCardTask.value
  if (!block || !task) return
  const result = await saveTaskCard(block, task, patch)
  if (result?.success) {
    showNotificationMessage('✅ Карточка задачи сохранена', 'success')
    closeTaskCardModal()
    return
  }
  showNotificationMessage(result?.message || '❌ Ошибка сохранения карточки задачи', 'error')
}

const deleteTaskCardModal = async () => {
  const block = taskCardBlock.value
  const task = taskCardTask.value
  if (!block || !task) return
  const result = await deleteTask(block, task)
  if (result?.success) {
    showNotificationMessage('🗑️ Задача удалена', 'success')
    closeTaskCardModal()
    return
  }
  showNotificationMessage(result?.message || '❌ Ошибка удаления задачи', 'error')
}
</script>

<style scoped>
.tracker-view {
  display: flex;
  flex-direction: column;
  min-height: 0;
  height: 100%;
  background: #f1f5f9;
  font-family: Inter, system-ui, -apple-system, 'Segoe UI', Roboto, Arial, sans-serif;
}
.tracker-toolbar {
  display: flex;
  align-items: center;
  gap: 16px;
  padding: 12px 16px;
  background: #ffffff;
  border-bottom: 1px solid #e2e8f0;
  flex-shrink: 0;
}
.tracker-filter {
  display: flex;
  align-items: center;
  gap: 10px;
  min-width: 0;
  width: min(320px, 100%);
}
.tracker-filter label {
  flex-shrink: 0;
  font-size: 0.85rem;
  font-weight: 600;
  color: #64748b;
}
.tracker-filter :deep(.app-select) {
  min-width: 0;
}
.tracker-toolbar-meta {
  margin-left: auto;
  font-size: 0.85rem;
  color: #64748b;
}
.tracker-empty {
  flex: 1;
  display: flex;
  align-items: center;
  justify-content: center;
  color: #94a3b8;
  font-size: 1rem;
}
.tracker-board {
  flex: 1;
  min-height: 0;
  display: grid;
  grid-template-columns: repeat(3, minmax(0, 1fr));
  gap: 12px;
  padding: 12px 16px 16px;
  overflow: auto;
}
.tracker-column {
  display: flex;
  flex-direction: column;
  min-height: 0;
  background: #e8edf3;
  border-radius: 10px;
  border: 1px solid transparent;
  overflow: hidden;
}
.tracker-column.is-drop-target {
  border-color: #93c5fd;
  background: #e0eafc;
}
.tracker-column-header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 8px;
  padding: 12px 14px 8px;
  flex-shrink: 0;
}
.tracker-column-title {
  font-size: 0.85rem;
  font-weight: 600;
  color: #0f172a;
}
.tracker-column.is-todo .tracker-column-title { color: #475569; }
.tracker-column.is-progress .tracker-column-title { color: #1d4ed8; }
.tracker-column.is-done .tracker-column-title { color: #15803d; }
.tracker-column-count {
  min-width: 22px;
  height: 22px;
  padding: 0 7px;
  border-radius: 999px;
  background: rgba(15, 23, 42, 0.08);
  color: #334155;
  font-size: 0.75rem;
  font-weight: 600;
  display: inline-flex;
  align-items: center;
  justify-content: center;
}
.tracker-column-body {
  flex: 1;
  min-height: 48px;
  padding: 4px 10px 12px;
  display: flex;
  flex-direction: column;
  gap: 8px;
  overflow: auto;
}
.tracker-column-empty {
  padding: 18px 8px;
  text-align: center;
  color: #94a3b8;
  font-size: 0.85rem;
}
.tracker-card {
  background: #ffffff;
  border: 1px solid #e2e8f0;
  border-radius: 8px;
  padding: 10px 12px;
  box-shadow: 0 1px 2px rgba(15, 23, 42, 0.06);
  cursor: pointer;
  user-select: none;
}
.tracker-card:hover {
  border-color: #cbd5e1;
  box-shadow: 0 4px 10px rgba(15, 23, 42, 0.08);
}
.tracker-card.is-dragging {
  opacity: 0.45;
}
.tracker-card.is-readonly {
  cursor: default;
}
.tracker-card-top {
  display: flex;
  align-items: flex-start;
  gap: 8px;
  min-width: 0;
}
.tracker-card-title {
  flex: 1;
  min-width: 0;
  font-size: 0.9rem;
  font-weight: 600;
  line-height: 1.35;
  color: #0f172a;
  overflow: hidden;
  display: -webkit-box;
  -webkit-line-clamp: 3;
  line-clamp: 3;
  -webkit-box-orient: vertical;
}
.tracker-card-link {
  width: 22px;
  height: 22px;
  flex-shrink: 0;
  border: none;
  border-radius: 4px;
  background: transparent;
  display: inline-flex;
  align-items: center;
  justify-content: center;
  cursor: pointer;
  padding: 0;
}
.tracker-card-link:hover {
  background: rgba(37, 99, 235, 0.08);
}
.tracker-card-link-icon {
  width: 16px;
  height: 16px;
  display: block;
}
.tracker-card-stage {
  margin: 6px 0 0 24px;
  font-size: 0.78rem;
  color: #64748b;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}
.tracker-card-meta {
  margin: 4px 0 0 24px;
  font-size: 0.75rem;
  color: #94a3b8;
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
  margin-top: 2px;
  padding: 0;
  border: 2px solid #94a3b8;
  border-radius: 50%;
  background: transparent;
  appearance: none;
  cursor: pointer;
}
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

@media (max-width: 900px) {
  .tracker-board {
    grid-template-columns: minmax(260px, 1fr);
    grid-auto-flow: column;
    grid-auto-columns: minmax(260px, 1fr);
  }
}
</style>
