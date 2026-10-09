<template>
  <div class="horizontal-container" :class="{ 'is-resize-cursor': Boolean(resizingMonth) || isResizeHandleHover }">
    <!-- Шапка с месяцами -->
    <div class="horizontal-header" ref="horizontalHeader">
      <!-- Как у timeline-container + timeline-grid: отступ слева на внешнем блоке, координаты — внутри track -->
      <div class="horizontal-header-container" :style="{ width: visibleHorizontalTotalWidth + 'px' }">
        <div class="horizontal-header-track">
          <div 
            v-for="(month, idx) in visibleMonthsData" 
            :key="month.index"
            class="horizontal-month-cell"
            :style="{ 
              left: month.visibleStartX + 'px',
              width: month.width + 'px'
            }"
          >
            <div class="month-label">{{ month.label }}</div>
            <div class="month-days">{{ month.days }} дн.</div>
            <div
              v-if="idx === visibleMonthsData.length - 1 && trailingMonthControl && (trailingMonthControl.showExtend || trailingMonthControl.showCollapse)"
              class="horizontal-trailing-month-wrap"
              :style="trailingMonthButtonStyleInCell(month)"
            >
              <Tooltip
                v-if="trailingMonthControl.showExtend"
                label="Показать следующий пустой месяц"
                position="bottom"
              >
                <button
                  type="button"
                  class="horizontal-trailing-month-btn"
                  aria-label="Показать следующий пустой месяц"
                  @click.stop.prevent="extendTrailingEmptyMonth"
                >
                  ▸
                </button>
              </Tooltip>
              <Tooltip
                v-else
                label="Скрыть пустой месяц"
                position="bottom"
              >
                <button
                  type="button"
                  class="horizontal-trailing-month-btn horizontal-trailing-month-btn--collapse"
                  aria-label="Скрыть пустой месяц"
                  @click.stop.prevent="collapseTrailingEmptyMonth"
                >
                  ‹
                </button>
              </Tooltip>
            </div>
            <Tooltip
              class="horizontal-month-resize-handle"
              label="Потяните для изменения ширины месяца"
              position="bottom"
            >
              <span
                class="horizontal-month-resize-hit"
                @pointerenter="onResizeHandleEnter"
                @pointerleave="onResizeHandleLeave"
                @pointerdown.stop.prevent="onMonthResizePointerDown($event, month)"
              />
            </Tooltip>
          </div>
        </div>
      </div>
      <Tooltip
        v-if="hasCustomMonthWidth"
        class="horizontal-reset-width-wrap"
        label="Сбросить ширину месяцев"
        position="bottom"
      >
      <button
        type="button"
        class="horizontal-reset-width-btn"
        aria-label="Сбросить ширину месяцев"
        @click.stop.prevent="onResetMonthWidths"
      >
        <svg class="horizontal-reset-width-icon" viewBox="0 0 24 24" aria-hidden="true">
          <path d="M12 4a8 8 0 1 1-7.2 4.5" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"/>
          <path d="M3 4h5v5" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>
        </svg>
      </button>
      </Tooltip>
    </div>

    <!-- Основной контент с прокруткой -->
    <div 
      class="timeline-wrapper" 
      ref="timelineWrapper" 
      @scroll="onTimelineScroll"
    >
      <div class="timeline-container" :style="{ width: visibleHorizontalTotalWidth + 'px' }">
        <div 
          class="timeline-grid"
          ref="timelineGrid"
          :style="{ height: totalHeight + 'px' }"
        >
          <!-- Линии для каждого дня (едва заметные) -->
          <div 
            v-for="day in visibleDays" 
            :key="'day-'+day.id"
            class="horizontal-day-line"
            :style="{ left: day.visibleCenterX + 'px' }"
          ></div>

          <!-- Линии начала каждого месяца (синие приглушенные) -->
          <div 
            v-for="month in visibleMonthPositions" 
            :key="'month-start-'+month.index"
            class="horizontal-month-line month-start"
            :style="{ left: month.visibleStartX + 'px' }"
          ></div>

          <!-- Линии конца каждого месяца (включая правый край последнего видимого) -->
          <div 
            v-for="month in visibleMonthPositions" 
            :key="'month-end-'+month.index"
            class="horizontal-month-line month-end"
            :style="{ left: month.visibleEndX + 'px' }"
          ></div>

          <!-- Полоса сегодняшнего дня -->
          <div 
            v-if="todayVisiblePosition > 0"
            class="today-line-horizontal"
            :style="{ left: todayVisiblePosition + 'px' }"
          >
            <div class="today-label-horizontal">Сегодня</div>
          </div>

          <!-- Блоки -->
          <BlockCard
            v-for="block in sortedBlocks"
            :key="block.id"
            :block="block"
            :compact="isShortStage(block)"
            :style="getVisibleBlockStyle(block)"
            :class="{ 'block-dragging': isDraggingBlock && draggedBlockId === block.id }"
            :drag-over-task="dragOverTask"
            :dragged-task="draggedTask"
            @edit-block="$emit('editBlock', block)"
            @add-task="onAddTaskAndOpenModal(block)"
            @cycle-task-status="(task, event) => cycleTaskStatus(block, task, event)"
            @start-task-edit="(task) => startTaskEdit(block, task)"
            @save-task-edit="(task, event) => saveTaskEdit(block, task, event)"
            @cancel-task-edit="(task) => cancelTaskEdit(task)"
            @open-task-card="(task) => openTaskCardModal(block, task)"
            @delete-task="(task) => deleteTask(block, task)"
            @task-drag-start="onTaskDragStart"
            @task-drag-end="onTaskDragEnd"
            @task-drag-over="onTaskDragOver"
            @task-drop="onTaskDrop"
            @task-drag-enter="onTaskDragEnter"
            @task-drag-leave="onTaskDragLeave"
            @block-drag-start="onBlockDragStart"
            @block-drag-end="onBlockDragEnd"
            @start-edit-date="startEditingDate(block)"
            @save-date="(dates) => saveDate(block, dates)"
            @cancel-edit-date="cancelDateEdit(block)"
          />
        </div>
      </div>
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
import { ref, computed, onMounted, onUnmounted, inject, watch, nextTick } from 'vue'
import { useDates } from '@/composables/useDates'
import { useTasks } from '@/composables/useTasks'
import { useNotification } from '@/composables/useNotification'
import BlockCard from '@/components/common/Block.vue'
import TaskCardModal from '@/components/common/TaskCardModal.vue'
import Tooltip from '@/components/common/Tooltip.vue'
import { compareStagesByPlanDates, getBlockPlanRange, layoutTimelineBlocks } from '@/utils/timelineSpanningLayout'

// Экран "По месяцам": месячная шкала с ресайзом и DnD этапов/задач.
// Получаем данные от родителя через inject
const blocks = inject('blocks')
const blocksActions = inject('blocksActions')

const { 
  calculateBlockHeight, 
  getBlockBackgroundColor, 
  updateBlockDate
} = blocksActions

const { 
  getAbsoluteMonthIndexFromDate, 
  visibleMonthsData,
  visibleMonthPositions,
  visibleDays,
  visibleHorizontalTotalWidth, 
  todayVisiblePosition,
  extendTrailingEmptyMonth,
  collapseTrailingEmptyMonth,
  trailingMonthControl,
  hasCustomMonthWidth,
  setVisibleMonthWidth,
  resetVisibleMonthWidth
} = useDates()

const { 
  addTask, 
  cycleTaskStatus, 
  deleteTask,
  startTaskEdit,
  saveTaskEdit,
  cancelTaskEdit,
  saveTaskCard,
  draggedTask,
  dragOverTask,
  onTaskDragStart,
  onTaskDragEnd,
  onTaskDragOver,
  onTaskDragEnter,
  onTaskDragLeave,
  onTaskDrop
} = useTasks()

const { showNotificationMessage } = useNotification()

// Refs для DOM
const timelineWrapper = ref(null)
const horizontalHeader = ref(null)
const timelineGrid = ref(null)
const MONTH_TASK_EXTRA_HEIGHT = 6
const measuredBlockHeights = ref({})
let blockResizeObserver = null
const resizingMonth = ref(null)
const isResizeHandleHover = ref(false)

// Состояние для перетаскивания блока
const draggedBlock = ref(null)
const isDraggingBlock = ref(false)
const draggedBlockId = ref(null)
const blockDragStartX = ref(0)
const blockDragStartY = ref(0)
const taskCardModalOpen = ref(false)
const taskCardBlock = ref(null)
const taskCardTask = ref(null)

const refreshMeasuredBlockHeights = async () => {
  await nextTick()
  const root = timelineGrid.value
  if (!root) return
  const nextHeights = {}
  root.querySelectorAll('.block[data-block-id]').forEach((node) => {
    const id = String(node.getAttribute('data-block-id') || '')
    if (!id) return
    nextHeights[id] = Math.ceil(node.offsetHeight)
  })
  const prev = measuredBlockHeights.value
  const same =
    Object.keys(nextHeights).length === Object.keys(prev).length &&
    Object.keys(nextHeights).every((id) => prev[id] === nextHeights[id])
  if (same) return
  measuredBlockHeights.value = nextHeights
}

const observeMonthBlockHeights = () => {
  const root = timelineGrid.value
  if (!root || !blockResizeObserver) return
  blockResizeObserver.disconnect()
  root.querySelectorAll('.block[data-block-id]').forEach((node) => {
    blockResizeObserver.observe(node)
  })
}

const SHORT_STAGE_DAYS = 15
const COLLAPSED_STAGE_HEIGHT = 40

const toLocalDay = (value) => {
  const raw = String(value || '').trim()
  const match = raw.match(/^(\d{4})-(\d{2})-(\d{2})/)
  if (match) return new Date(Number(match[1]), Number(match[2]) - 1, Number(match[3]))
  const date = value instanceof Date ? value : new Date(value)
  if (Number.isNaN(date.getTime())) return null
  return new Date(date.getFullYear(), date.getMonth(), date.getDate())
}

const dayKey = (date) => {
  const year = date.getFullYear()
  const month = String(date.getMonth() + 1).padStart(2, '0')
  const day = String(date.getDate()).padStart(2, '0')
  return `${year}-${month}-${day}`
}

const getStageDayRange = (block) => {
  const { start, end } = getBlockPlanRange(block)
  const from = toLocalDay(start)
  const to = toLocalDay(end)
  if (!from || !to) return null
  return from.getTime() <= to.getTime() ? { from, to } : { from: to, to: from }
}

const stageDurationDays = (block) => {
  const range = getStageDayRange(block)
  if (!range) return null
  return Math.round((range.to.getTime() - range.from.getTime()) / 86400000) + 1
}

const isShortStage = (block) => {
  const days = stageDurationDays(block)
  return days != null && days < SHORT_STAGE_DAYS
}

const getStageDayGeometry = (block) => {
  const range = getStageDayRange(block)
  const days = visibleDays.value
  if (!range || !days.length) return null
  const fromKey = dayKey(range.from)
  const toKey = dayKey(range.to)
  let startDay = null
  let endDay = null
  for (const day of days) {
    const key = dayKey(day.date)
    if (key < fromKey || key > toKey) continue
    if (!startDay) startDay = day
    endDay = day
  }
  if (!startDay || !endDay) return null
  return {
    left: startDay.startX,
    width: Math.max(endDay.endX - startDay.startX, endDay.endX - endDay.startX)
  }
}

const getMonthLayoutHeight = (block) => {
  if (isShortStage(block)) return COLLAPSED_STAGE_HEIGHT
  const estimatedHeight = calculateBlockHeight(block)
  const tasksCount = Array.isArray(block?.tasks) ? block.tasks.length : 0
  return estimatedHeight + tasksCount * MONTH_TASK_EXTRA_HEIGHT
}

const openTaskCardModal = (block, task) => {
  if (!block || !task) return
  taskCardBlock.value = block
  taskCardTask.value = task
  taskCardModalOpen.value = true
}

const closeTaskCardModal = () => {
  taskCardModalOpen.value = false
  taskCardBlock.value = null
  taskCardTask.value = null
}

const saveTaskCardModal = async (patch) => {
  if (!taskCardBlock.value || !taskCardTask.value) return
  const result = await saveTaskCard(taskCardBlock.value, taskCardTask.value, patch)
  if (result?.success) {
    closeTaskCardModal()
    showNotificationMessage('✅ Карточка задачи сохранена', 'success')
  } else {
    showNotificationMessage(result?.message || '❌ Ошибка сохранения карточки задачи', 'error')
  }
}

const deleteTaskCardModal = async () => {
  if (!taskCardBlock.value || !taskCardTask.value) return
  const result = await deleteTask(taskCardBlock.value, taskCardTask.value)
  if (result?.success) {
    closeTaskCardModal()
    showNotificationMessage('🗑️ Задача удалена', 'success')
  } else {
    showNotificationMessage(result?.message || '❌ Ошибка удаления задачи', 'error')
  }
}

const onAddTaskAndOpenModal = async (block) => {
  if (!block) return
  const result = await addTask(block)
  if (!result?.success) return
  const freshBlock = (blocks?.value || []).find((item) => String(item?.id) === String(block.id)) || block
  const tasks = Array.isArray(freshBlock?.tasks) ? freshBlock.tasks : []
  if (!tasks.length) return
  const createdTask = tasks.find((item) => String(item?.id) === String(result?.newTaskId)) || tasks[tasks.length - 1]
  if (!createdTask) return
  openTaskCardModal(freshBlock, createdTask)
}

// Сортировка блоков по дате
const sortedBlocks = computed(() => {
  if (!blocks?.value) return []
  return [...blocks.value].sort((a, b) => compareStagesByPlanDates(a, b))
})

const monthLayout = computed(() =>
  layoutTimelineBlocks({
    columns: visibleMonthsData.value,
    blocks: sortedBlocks.value,
    heights: measuredBlockHeights.value,
    estimateHeight: getMonthLayoutHeight,
    getIndexFromDate: getAbsoluteMonthIndexFromDate
  })
)

const totalHeight = computed(() => {
  const columnHeights = monthLayout.value.columnBodyMinHeightsPx || []
  const maxHeight = columnHeights.length ? Math.max(...columnHeights) : 0
  return Math.max(maxHeight + 50, 500)
})

const getVisibleBlockPosition = (block) => {
  return monthLayout.value.positions[String(block?.id)] || null
}

const getVisibleBlockStyle = (block) => {
  const position = getVisibleBlockPosition(block)
  if (!position) {
    return { display: 'none' }
  }
  const days = getStageDayGeometry(block)
  return {
    left: (days ? days.left : position.left) + 'px',
    top: position.top + 'px',
    width: (days ? days.width : position.width) + 'px',
    backgroundColor: getBlockBackgroundColor(block)
  }
}

// Перетаскивание блока за шапку
const onBlockDragStart = (event, block) => {
  event.stopPropagation()
  if (event.target.tagName === 'BUTTON') {
    event.preventDefault()
    return
  }
  
  draggedBlock.value = block
  draggedBlockId.value = block.id
  isDraggingBlock.value = true
  blockDragStartX.value = event.clientX
  blockDragStartY.value = event.clientY
  
  event.dataTransfer.setData('text/plain', JSON.stringify({
    blockId: block.id,
    type: 'block'
  }))
  event.dataTransfer.effectAllowed = 'move'
  
  const canvas = document.createElement('canvas')
  canvas.width = 1
  canvas.height = 1
  event.dataTransfer.setDragImage(canvas, 0, 0)
  
  document.body.classList.add('is-dragging')
}

const onBlockDragEnd = () => {
  draggedBlock.value = null
  draggedBlockId.value = null
  isDraggingBlock.value = false
  document.body.classList.remove('is-dragging')
}

// Удаление блока
const startEditingDate = (block) => {
  block.editingDate = true
}

const saveDate = async (block, dates) => {
  const startDate = dates?.startDate ?? block.startDate
  const releaseDate = dates?.releaseDate ?? block.releaseDate
  const keepOpen = Boolean(dates?.keepOpen)
  if (!startDate && !releaseDate) {
    cancelDateEdit(block)
    return
  }
  if (startDate === (block.startDate || '') && releaseDate === (block.releaseDate || '')) {
    if (!keepOpen) cancelDateEdit(block)
    return
  }
  const result = await updateBlockDate(block, {
    startDate,
    releaseDate,
    changedField: dates?.changedField
  })
  if (result.success) {
    if (!keepOpen) block.editingDate = false
    showNotificationMessage('✅ Даты этапа обновлены', 'success')
  } else {
    showNotificationMessage('❌ Ошибка обновления дат', 'error')
  }
}

const cancelDateEdit = (block) => {
  block.editingDate = false
}

// Синхронизация скролла
const onTimelineScroll = () => {
  if (!timelineWrapper.value || !horizontalHeader.value) return
  const scrollLeft = timelineWrapper.value.scrollLeft
  horizontalHeader.value.scrollLeft = scrollLeft
}

const onHeaderScroll = () => {
  if (!timelineWrapper.value || !horizontalHeader.value) return
  const scrollLeft = horizontalHeader.value.scrollLeft
  timelineWrapper.value.scrollLeft = scrollLeft
}

const onMonthResizePointerMove = (event) => {
  const state = resizingMonth.value
  if (!state) return
  const deltaX = event.clientX - state.startClientX
  setVisibleMonthWidth(state.monthIndex, state.startWidth + deltaX)
}

const stopMonthResize = () => {
  if (!resizingMonth.value) return
  resizingMonth.value = null
  isResizeHandleHover.value = false
  window.removeEventListener('pointermove', onMonthResizePointerMove)
  window.removeEventListener('pointerup', stopMonthResize)
  window.removeEventListener('pointercancel', stopMonthResize)
}

const onMonthResizePointerDown = (event, month) => {
  const monthIndex = Number(month?.index)
  const startWidth = Number(month?.width)
  if (!Number.isFinite(monthIndex) || !Number.isFinite(startWidth)) return
  resizingMonth.value = {
    monthIndex,
    startWidth,
    startClientX: event.clientX
  }
  window.addEventListener('pointermove', onMonthResizePointerMove)
  window.addEventListener('pointerup', stopMonthResize)
  window.addEventListener('pointercancel', stopMonthResize)
}

const onResizeHandleEnter = () => {
  isResizeHandleHover.value = true
}

const onResizeHandleLeave = () => {
  if (resizingMonth.value) return
  isResizeHandleHover.value = false
}

const onResetMonthWidths = () => {
  stopMonthResize()
  const widestSingleColumnWidth = visibleMonthsData.value.reduce((maxWidth, month) => {
    const width = Math.round(Number(month?.width || 0) * 0.9)
    return Number.isFinite(width) ? Math.max(maxWidth, width) : maxWidth
  }, 0)
  resetVisibleMonthWidth(widestSingleColumnWidth)
}

defineEmits(['editBlock'])

/** Кнопка +/‹ на последнем дне месяца — позиция относительно ячейки шапки (чтобы не перекрывалась соседними месяцами). */
const trailingMonthButtonStyleInCell = (month) => {
  const tc = trailingMonthControl.value
  if (!tc || !month) return {}
  return {
    left: `${tc.centerX - month.visibleStartX + 20}px`,
    transform: 'translateX(-50%)'
  }
}

onMounted(() => {
  if (horizontalHeader.value) {
    horizontalHeader.value.addEventListener('scroll', onHeaderScroll)
  }
  blockResizeObserver = new ResizeObserver(() => {
    refreshMeasuredBlockHeights()
  })
  window.addEventListener('resize', refreshMeasuredBlockHeights)
  refreshMeasuredBlockHeights()
  observeMonthBlockHeights()
})

onUnmounted(() => {
  if (horizontalHeader.value) {
    horizontalHeader.value.removeEventListener('scroll', onHeaderScroll)
  }
  if (blockResizeObserver) {
    blockResizeObserver.disconnect()
    blockResizeObserver = null
  }
  window.removeEventListener('resize', refreshMeasuredBlockHeights)
  stopMonthResize()
})

watch(
  sortedBlocks,
  () => {
    refreshMeasuredBlockHeights()
    observeMonthBlockHeights()
  },
  { deep: true, immediate: true }
)
watch(visibleHorizontalTotalWidth, () => {
  refreshMeasuredBlockHeights()
  observeMonthBlockHeights()
})
</script>

<style scoped>
.horizontal-container {
  display: flex;
  flex-direction: column;
  height: 100%;
  overflow: hidden;
}

/* Шапка с месяцами */
.horizontal-header {
  flex-shrink: 0;
  height: 60px;
  background: white;
  border-bottom: 2px solid #3b82f6;
  overflow-x: auto;
  overflow-y: hidden;
  scrollbar-width: none;
  -ms-overflow-style: none;
  position: relative;
  z-index: 100;
}

.horizontal-header::-webkit-scrollbar {
  display: none;
}

.horizontal-header-container {
  position: relative;
  height: 100%;
  min-width: 100%;
  padding-left: 20px;
  box-sizing: border-box;
}

.horizontal-header-track {
  position: relative;
  height: 100%;
  /* Совпадает с областью позиционирования timeline-grid внутри timeline-container */
  left: 2px;
}

.horizontal-month-cell {
  position: absolute;
  top: 0;
  height: 100%;
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  background: white;
  z-index: 10;
  padding: 4px;
  box-sizing: border-box;
}

.horizontal-month-resize-handle {
  position: absolute;
  top: 0;
  right: -7px;
  width: 14px;
  height: 100%;
  display: block;
  cursor: grab;
  z-index: 40;
  background: linear-gradient(
    to right,
    rgba(59, 130, 246, 0) 0%,
    rgba(59, 130, 246, 0.08) 50%,
    rgba(59, 130, 246, 0) 100%
  );
}
.horizontal-month-resize-hit {
  display: block;
  width: 100%;
  height: 100%;
}
.horizontal-month-resize-handle::before {
  content: '';
  position: absolute;
  top: 50%;
  left: 50%;
  width: 2px;
  height: 24px;
  transform: translate(-50%, -50%);
  background: rgba(59, 130, 246, 0.55);
  border-radius: 999px;
  opacity: 0.75;
  transition: opacity 0.15s ease;
}
.horizontal-month-cell:hover .horizontal-month-resize-handle::before {
  opacity: 1;
}
.horizontal-container.is-resize-cursor,
.horizontal-container.is-resize-cursor * {
  cursor: grabbing !important;
}

.horizontal-reset-width-wrap {
  position: absolute;
  top: 8px;
  left: 8px;
  z-index: 35;
}
.horizontal-reset-width-btn {
  width: 28px;
  height: 28px;
  padding: 0;
  border-radius: 999px;
  border: 1px solid #93c5fd;
  background: #eff6ff;
  color: #1d4ed8;
  cursor: pointer;
  display: inline-flex;
  align-items: center;
  justify-content: center;
}
.horizontal-reset-width-btn:hover {
  background: #dbeafe;
}
.horizontal-reset-width-icon {
  width: 16px;
  height: 16px;
  display: block;
}

.horizontal-month-cell::after {
  content: '';
  position: absolute;
  top: 0;
  bottom: 0;
  right: -1px;
  width: 1px;
  background: #e2e8f0;
  pointer-events: none;
}

.horizontal-trailing-month-wrap {
  position: absolute;
  top: 0;
  bottom: 0;
  width: 40px;
  margin-left: 0;
  display: flex;
  align-items: center;
  justify-content: center;
  z-index: 25;
  pointer-events: auto;
}

.horizontal-trailing-month-btn {
  width: 13px;
  height: 44px;
  border-radius: 14px;
  border: 1px solid #3b82f6;
  background: #eff6ff;
  color: #1d4ed8;
  font-size: 1rem;
  font-weight: 700;
  line-height: 1;
  cursor: pointer;
  padding: 0;
  display: flex;
  align-items: center;
  justify-content: center;
  opacity: 0.88;
  transform: scale(1);
  transition: opacity 0.15s ease, transform 0.15s ease, background 0.15s ease, box-shadow 0.15s ease;
  box-shadow: 0 1px 4px rgba(37, 99, 235, 0.25);
}

.horizontal-trailing-month-wrap:hover .horizontal-trailing-month-btn,
.horizontal-trailing-month-btn:focus-visible {
  opacity: 1;
  transform: scale(1.06);
  box-shadow: 0 2px 8px rgba(37, 99, 235, 0.35);
}

.horizontal-trailing-month-btn:hover {
  background: #dbeafe;
}

.horizontal-trailing-month-btn--collapse {
  font-size: 1.15rem;
  font-weight: 700;
  padding-bottom: 0;
}

.month-label {
  font-weight: 600;
  font-size: 0.9rem;
  color: #1e293b;
}

.month-days {
  font-size: 0.7rem;
  color: #64748b;
  margin-top: 2px;
}

/* Основной контент */
.timeline-wrapper {
  flex: 1;
  overflow-x: auto;
  overflow-y: auto;
  position: relative;
  background: #ffffff;
}

.timeline-wrapper::-webkit-scrollbar {
  width: 8px;
  height: 8px;
}

.timeline-wrapper::-webkit-scrollbar-track {
  background: #f1f5f9;
  border-radius: 8px;
}

.timeline-wrapper::-webkit-scrollbar-thumb {
  background: #cbd5e1;
  border-radius: 8px;
}

.timeline-container {
  position: relative;
  padding-left: 20px;
  min-width: min-content;
  box-sizing: border-box;
}

.timeline-grid {
  position: relative;
  z-index: 1;
  min-height: 100vh;
  padding-bottom: 100px;
}

/* Линии дней - едва заметные */
.horizontal-day-line {
  position: absolute;
  top: 0;
  bottom: 0;
  width: 1px;
  background: rgba(203, 213, 225, 0.2);
  pointer-events: none;
  z-index: 1;
  transform: translateX(-50%);
  height: 100%;
}

/* Линии месяцев - синие приглушенные */
.horizontal-month-line {
  position: absolute;
  top: 0;
  bottom: 0;
  width: 2px;
  pointer-events: none;
  z-index: 10;
  height: 100%;
  opacity: 0.5;
}

.month-start {
  background: #3b82f6;
}

.month-end {
  background: #3b82f6;
}

/* Полоса сегодня */
.today-line-horizontal {
  position: absolute;
  top: 0;
  bottom: 0;
  width: 3px;
  background: #ef4444;
  z-index: 20;
  pointer-events: none;
  transform: translateX(-50%);
  box-shadow: 0 0 8px rgba(239, 68, 68, 0.5);
  height: 100%;
}

.today-label-horizontal {
  position: absolute;
  top: -25px;
  left: 50%;
  transform: translateX(-50%);
  background: #ef4444;
  color: white;
  font-size: 0.7rem;
  font-weight: 600;
  padding: 2px 8px;
  border-radius: 12px;
  white-space: nowrap;
  z-index: 200;
}

.block.block-dragging {
  opacity: 0.8;
  cursor: grabbing;
  z-index: 100;
}

</style>