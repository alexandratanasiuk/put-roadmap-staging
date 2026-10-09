<template>
  <div
    v-if="block"
    class="modal-overlay"
    @pointerdown.self="onOverlayPointerDown"
    @pointermove.self="onOverlayPointerMove"
    @pointerup.self="onOverlayPointerUp"
    @pointercancel.self="onOverlayPointerCancel"
  >
    <div class="modal" @click.stop>
      <div class="modal-header">
        <h3>{{ isReadOnly ? 'Просмотр этапа' : 'Редактировать этап' }}</h3>
        <button class="close-btn" type="button" aria-label="Закрыть" @click="handleClose">×</button>
      </div>
      
      <div class="modal-two-columns">
        <div class="modal-left">
          <div class="form-group">
            <label>Название</label>
            <textarea
              v-model="editingBlock.title"
              class="stage-name-input"
              rows="2"
              placeholder="Название этапа"
              :readonly="isReadOnly"
            ></textarea>
          </div>
          
          <div class="form-group">
            <div class="form-label-row">
              <label>Описание</label>
              <Tooltip :label="descriptionCopied ? 'Скопировано' : 'Копировать описание'">
                <button
                  type="button"
                  class="icon-btn"
                  :disabled="!String(editingBlock.description || '').trim()"
                  aria-label="Копировать описание"
                  @click="copyDescription"
                >
                  <svg viewBox="0 0 20 20" width="16" height="16" aria-hidden="true">
                    <rect x="7" y="7" width="9" height="10" rx="1.5" fill="none" stroke="currentColor" stroke-width="1.5"/>
                    <path d="M5 13H4.5A1.5 1.5 0 0 1 3 11.5v-8A1.5 1.5 0 0 1 4.5 2h8A1.5 1.5 0 0 1 14 3.5V5" fill="none" stroke="currentColor" stroke-width="1.5"/>
                  </svg>
                </button>
              </Tooltip>
            </div>
            <textarea
              v-model="editingBlock.description"
              class="stage-description-input"
              rows="7"
              placeholder="Краткое описание целей этапа..."
              :readonly="isReadOnly"
            ></textarea>
          </div>
          
          <div class="form-row">
            <div class="form-group">
              <label>Дата начала</label>
              <input v-model="editingBlock.startDate" type="date" :disabled="isReadOnly">
            </div>
            <div class="form-group">
              <label>Дата окончания</label>
              <input v-model="editingBlock.releaseDate" type="date" :disabled="isReadOnly">
            </div>
          </div>

          <div class="form-group">
            <label>Трудозатраты, ч</label>
            <input
              v-model.number="editingBlock.effort"
              class="stage-full-input"
              type="number"
              min="0"
              step="1"
              :readonly="isReadOnly"
              @input="normalizeBlockEffort"
            >
          </div>

          <div class="form-group">
            <label>Владелец этапа</label>
            <AppSelect
              v-model="editingBlock.ownerUsername"
              :options="ownerOptions"
              :disabled="isReadOnly"
              placeholder="Выберите владельца"
            />
          </div>
          <div class="form-group">
            <label>Проект</label>
            <AppSelect
              v-model="editingBlock.projectId"
              :options="projectOptions"
              :disabled="isReadOnly || !projects.length"
              placeholder="Нет проектов"
            />
          </div>
        </div>
        
        <div class="modal-right">
          <div class="tasks-header-modal">
            <label>Элементы</label>
            <button
              v-if="!isReadOnly"
              type="button"
              class="btn-add-task-modal"
              @click="addTaskInModal"
            >
              + Добавить элемент
            </button>
          </div>
          
          <div class="modal-tasks-list" :class="{ 'is-empty': !editingBlock.tasks?.length }">
            <div
              v-for="task in editingBlock.tasks"
              :key="task.id"
              class="modal-task-wrap"
              :class="{ 'is-expanded': taskEditorTaskId === task.id }"
            >
              <div
                class="modal-task-item"
                :class="{
                  'is-active': taskEditorTaskId === task.id,
                  'task-done-modal': task.status === 'done'
                }"
                @click="openTaskEditor(task)"
              >
                <button
                  type="button"
                  class="task-status"
                  :class="statusClass(task)"
                  :disabled="isReadOnly"
                  :aria-label="statusLabel(task)"
                  @click.stop="cycleTaskStatusInModal(task)"
                ></button>
                <Tooltip :label="task.title" fill>
                  <span class="modal-task-title">{{ task.title }}</span>
                </Tooltip>
                <div class="modal-task-meta">
                  <button
                    v-if="hasTaskLinkUrl(task)"
                    type="button"
                    class="modal-task-link"
                    aria-label="Открыть ссылку"
                    @click.stop="openTaskLink(task)"
                  >
                    <img class="modal-task-link-icon" :src="linkIcon" alt="">
                  </button>
                  <span class="task-effort-value">{{ task.effort || 0 }} ч</span>
                </div>
              </div>

              <div
                v-if="!isReadOnly && taskEditorTaskId === task.id"
                class="modal-task-editor-panel"
                :data-task-editor-id="String(task.id)"
                @click.stop
              >
                <label class="modal-task-link-label">Название</label>
                <textarea
                  v-model="taskEditorDraft.title"
                  class="modal-task-link-field modal-task-name-field"
                  rows="2"
                  placeholder="Название элемента"
                ></textarea>

                <label class="modal-task-link-label">Ссылка</label>
                <div class="modal-task-link-row">
                  <input
                    v-model="taskEditorDraft.linkUrl"
                    type="url"
                    class="modal-task-link-field"
                    :id="`task-editor-link-${task.id}`"
                    placeholder="https://..."
                    @click.stop
                  >
                  <button
                    v-if="taskEditorDraft.linkUrl"
                    type="button"
                    class="icon-btn"
                    aria-label="Очистить ссылку"
                    @click="clearTaskEditorLink"
                  >×</button>
                </div>

                <div class="form-row modal-task-dates-row">
                  <label class="modal-task-link-label modal-task-date-label">
                    Дата начала
                    <input
                      v-model="taskEditorDraft.startDate"
                      type="date"
                      class="modal-task-link-field"
                      :min="getTaskStartMinDate()"
                      :max="getTaskStartMaxDate()"
                    >
                  </label>
                  <label class="modal-task-link-label modal-task-date-label">
                    Дата окончания
                    <input
                      v-model="taskEditorDraft.releaseDate"
                      type="date"
                      class="modal-task-link-field"
                      :min="getTaskEndMinDate()"
                      :max="getTaskEndMaxDate()"
                    >
                  </label>
                </div>

                <label class="modal-task-link-label">Трудозатраты, ч</label>
                <input
                  v-model.number="taskEditorDraft.effort"
                  type="number"
                  class="modal-task-link-field modal-task-effort-field"
                  min="0"
                  step="1"
                  placeholder="0"
                >

                <TaskAttachments
                  :block-id="editingBlock.id"
                  :task-id="task.id"
                />

                <div class="modal-task-editor-actions">
                  <button type="button" class="btn btn-danger" @click="deleteTaskInModal(task)">
                    Удалить
                  </button>
                  <div class="footer-actions">
                    <button type="button" class="btn btn-text" @click="cancelTaskEditor">Отмена</button>
                    <button type="button" class="btn btn-secondary" @click="saveTaskEditor(task)">Сохранить</button>
                  </div>
                </div>
              </div>
            </div>
            
            <div v-if="!editingBlock.tasks || editingBlock.tasks.length === 0" class="modal-tasks-empty">
              Нет элементов
            </div>
          </div>
          
          <div class="tasks-total-effort" v-if="editingBlock.tasks && editingBlock.tasks.length > 0">
            <span class="total-label">Сумма по элементам</span>
            <span class="total-value">{{ getTotalTasksEffort() }} ч</span>
          </div>
        </div>
      </div>
      
      <div class="modal-footer">
        <button v-if="!isReadOnly" type="button" class="btn btn-danger" @click="handleDelete">Удалить</button>
        <span v-else></span>
        <div class="footer-actions">
          <button type="button" class="btn btn-text" @click="handleClose">{{ isReadOnly ? 'Закрыть' : 'Отмена' }}</button>
          <button v-if="!isReadOnly" type="button" class="btn btn-secondary" @click="handleSave">Сохранить</button>
        </div>
      </div>
    </div>
  </div>
</template>

<script setup>
import { ref, watch, onMounted, nextTick, computed } from 'vue'
import axios from 'axios'
import { useAuth } from '@/composables/useAuth'
import { useProjects } from '@/composables/useProjects'
import {
  normalizeTasksArray,
  removePredecessorIdFromAllTasks
} from '@/utils/taskModel'
import Tooltip from './Tooltip.vue'
import AppSelect from './AppSelect.vue'
import TaskAttachments from './TaskAttachments.vue'
import linkIcon from '@/assets/link-icon.png'

// Модалка редактирует один этап целиком (поля этапа + вложенные задачи).
const props = defineProps({
  block: {
    type: Object,
    default: null
  }
})

// close — закрытие, save — сохранить этап, delete — удалить этап.
const emit = defineEmits(['close', 'save', 'delete'])

// Глобальные зависимости: API/auth режим и список проектов для привязки этапа.
const { API_URL, isReadOnly } = useAuth()
const { projects, activeProjectId, loadProjects } = useProjects()
const owners = ref([])
/** id задачи, для которой открыта мини-панель редактирования. */
const taskEditorTaskId = ref(null)

// Черновик mini-редактора задачи (ссылка/даты/оценка) внутри модалки этапа.
const taskEditorDraft = ref({
  title: '',
  linkUrl: '',
  startDate: '',
  releaseDate: '',
  effort: 0
})
const isEditingBlockEffort = ref(false)
const descriptionCopied = ref(false)
let descriptionCopyTimer = null

// Контроль pointer-состояния оверлея, чтобы не закрывать модалку при drag-жестах.
const overlayPointerState = ref({
  active: false,
  pointerId: null,
  startX: 0,
  startY: 0,
  moved: false
})

// Нормализаторы ссылок и дат для защиты модели от "грязных" значений.
const normalizeLinkUrl = (raw) => {
  if (!raw || typeof raw !== 'string') return ''
  const trimmed = raw.trim()
  if (!trimmed) return ''
  if (/^https?:\/\//i.test(trimmed)) return trimmed
  return `https://${trimmed}`
}

const hasTaskLinkUrl = (task) => Boolean(normalizeLinkUrl(task?.linkUrl || ''))
const openTaskLink = (task) => {
  const url = normalizeLinkUrl(task?.linkUrl || '')
  if (!url) return
  window.open(url, '_blank', 'noopener,noreferrer')
}

const normalizeDateValue = (value) => {
  if (!value || typeof value !== 'string') return ''
  const trimmed = value.trim()
  return /^\d{4}-\d{2}-\d{2}$/.test(trimmed) ? trimmed : ''
}

const normalizeTaskDateRange = (startDateRaw, releaseDateRaw) => {
  let startDate = normalizeDateValue(startDateRaw)
  let releaseDate = normalizeDateValue(releaseDateRaw)
  if (startDate && releaseDate && startDate > releaseDate) {
    releaseDate = startDate
  }
  return { startDate, releaseDate }
}

const clampTaskDatesToStage = (startDateRaw, releaseDateRaw) => {
  const stageStart = normalizeDateValue(editingBlock.value.startDate)
  const stageEnd = normalizeDateValue(editingBlock.value.releaseDate)

  let startDate = normalizeDateValue(startDateRaw)
  let releaseDate = normalizeDateValue(releaseDateRaw)

  if (stageStart && startDate && startDate < stageStart) startDate = stageStart
  if (stageEnd && startDate && startDate > stageEnd) startDate = stageEnd
  if (stageStart && releaseDate && releaseDate < stageStart) releaseDate = stageStart
  if (stageEnd && releaseDate && releaseDate > stageEnd) releaseDate = stageEnd

  if (startDate && releaseDate && startDate > releaseDate) {
    releaseDate = startDate
  }

  return { startDate, releaseDate }
}

// Границы date-input задач считаются от дат этапа и текущего draft.
const getTaskStartMinDate = () => normalizeDateValue(editingBlock.value.startDate)
const getTaskStartMaxDate = () => {
  const stageEnd = normalizeDateValue(editingBlock.value.releaseDate)
  const draftEnd = normalizeDateValue(taskEditorDraft.value.releaseDate)
  return draftEnd || stageEnd
}
const getTaskEndMinDate = () => {
  const stageStart = normalizeDateValue(editingBlock.value.startDate)
  const draftStart = normalizeDateValue(taskEditorDraft.value.startDate)
  return draftStart || stageStart
}
const getTaskEndMaxDate = () => normalizeDateValue(editingBlock.value.releaseDate)

// Открывает inline-панель редактирования выбранной задачи и инициализирует draft.
const openTaskEditor = (task) => {
  if (isReadOnly.value) return
  if (taskEditorTaskId.value === task.id) {
    taskEditorTaskId.value = null
    return
  }
  taskEditorTaskId.value = task.id
  const { startDate, releaseDate } = clampTaskDatesToStage(task.startDate, task.releaseDate)
  taskEditorDraft.value = {
    title: task.title || '',
    linkUrl: task.linkUrl || '',
    startDate,
    releaseDate,
    effort: Number.isFinite(Number(task.effort)) ? Number(task.effort) : 0
  }
  focusTaskEditorNameInput()
}

const focusTaskEditorNameInput = async () => {
  await nextTick()
  const panel = document.querySelector(`[data-task-editor-id="${taskEditorTaskId.value}"]`)
  const el = panel?.querySelector('.modal-task-name-field')
  if (!el) return
  el.focus({ preventScroll: true })
  if (typeof el.select === 'function') el.select()
}

const cancelTaskEditor = () => {
  taskEditorTaskId.value = null
}

const clearTaskEditorLink = () => {
  taskEditorDraft.value.linkUrl = ''
}

const saveTaskEditor = (task) => {
  if (isReadOnly.value) return
  const { startDate, releaseDate } = clampTaskDatesToStage(
    taskEditorDraft.value.startDate,
    taskEditorDraft.value.releaseDate
  )
  const title = String(taskEditorDraft.value.title || '').trim()
  if (title) task.title = title
  task.linkUrl = normalizeLinkUrl(taskEditorDraft.value.linkUrl)
  task.startDate = startDate
  task.releaseDate = releaseDate
  task.effort = Math.max(0, Number(taskEditorDraft.value.effort) || 0)
  taskEditorTaskId.value = null
}

const onTaskTitleClickInModal = (task) => {
  if (isReadOnly.value) {
    if (hasTaskLinkUrl(task)) openTaskLink(task)
    return
  }
  if (hasTaskLinkUrl(task)) {
    openTaskLink(task)
    return
  }
  startTaskEditInModal(task)
}

// Локальная копия этапа: редактируем безопасно, не мутируя props.block напрямую.
const editingBlock = ref({
  id: '',
  title: '',
  description: '',
  startDate: '',
  releaseDate: '',
  effort: 0,
  ownerUsername: '',
  projectId: '',
  completed: false,
  tasks: []
})

// Синхронизация локальной копии с входным этапом при открытии/смене модалки.
watch(() => props.block, (newBlock) => {
  taskEditorTaskId.value = null
  isEditingBlockEffort.value = false
  if (newBlock) {
    editingBlock.value = JSON.parse(JSON.stringify(newBlock)) // глубокое копирование
    // Убедимся, что tasks существует и у задач есть isEditingInModal
    if (!editingBlock.value.tasks) {
      editingBlock.value.tasks = []
    } else {
      editingBlock.value.tasks = normalizeTasksArray(editingBlock.value.tasks)
    }
    editingBlock.value.tasks.forEach(task => {
      task.isEditingInModal = false
    })
    if (!editingBlock.value.ownerUsername && owners.value.length) {
      editingBlock.value.ownerUsername = owners.value[0].username
    }
    if (!editingBlock.value.projectId) {
      editingBlock.value.projectId = activeProjectId.value || projects.value[0]?.id || ''
    }
  }
}, { immediate: true, deep: true })

// Справочники для формы этапа: владельцы и проекты.
const loadOwners = async () => {
  try {
    const response = await axios.get(`${API_URL}/users`, { timeout: 12000 })
    owners.value = Array.isArray(response.data) ? response.data : []
    if (!editingBlock.value.ownerUsername && owners.value.length) {
      editingBlock.value.ownerUsername = owners.value[0].username
    }
  } catch (error) {
    console.error('❌ Ошибка загрузки владельцев:', error)
    owners.value = []
  }
}

onMounted(loadOwners)
onMounted(loadProjects)

const ownerOptions = computed(() =>
  (owners.value || []).map((user) => ({
    value: user.username,
    label: `${user.username}${user.role === 'admin' ? ' (admin)' : ''}`
  }))
)

const projectOptions = computed(() =>
  (projects.value || []).map((project) => ({
    value: project.id,
    label: project.name
  }))
)

watch(projects, (list) => {
  if (!editingBlock.value || editingBlock.value.projectId) return
  editingBlock.value.projectId = activeProjectId.value || list?.[0]?.id || ''
}, { deep: true })

// Локальные helper-методы отображения статусов задач в модалке этапа.
const statusClass = (task) => {
  if (task?.status === 'done') return 'task-status_done'
  if (task?.status === 'progress') return 'task-status_progress'
  return 'task-status_todo'
}

const statusLabel = (task) => {
  if (task?.status === 'done') return 'Выполнено'
  if (task?.status === 'progress') return 'В работе'
  return 'Не начато'
}

const copyDescription = async () => {
  const text = String(editingBlock.value?.description || '').trim()
  if (!text) return
  try {
    await navigator.clipboard.writeText(text)
    descriptionCopied.value = true
    clearTimeout(descriptionCopyTimer)
    descriptionCopyTimer = setTimeout(() => {
      descriptionCopied.value = false
    }, 1600)
  } catch (error) {
    console.error('Не удалось скопировать описание', error)
  }
}

const getNextStatus = (currentStatus) => {
  switch(currentStatus) {
    case 'todo': return 'progress'
    case 'progress': return 'done'
    case 'done': return 'todo'
    default: return 'todo'
  }
}

const normalizeBlockEffort = () => {
  const raw = Number(editingBlock.value?.effort)
  if (!Number.isFinite(raw)) {
    editingBlock.value.effort = 0
    return
  }
  editingBlock.value.effort = Math.max(0, Math.min(1000, Math.round(raw)))
}

const addTaskInModal = () => {
  if (isReadOnly.value) return
  const newTask = {
    id: Date.now() + '-' + Math.random().toString(36).substr(2, 9),
    title: 'Новый элемент',
    linkUrl: '',
    linkNote: '',
    status: 'todo',
    effort: 0,
    order: editingBlock.value.tasks ? editingBlock.value.tasks.length : 0,
    predecessorIds: []
  }
  
  if (!editingBlock.value.tasks) editingBlock.value.tasks = []
  editingBlock.value.tasks.push(newTask)
  openTaskEditor(newTask)
}

const cycleTaskStatusInModal = (task) => {
  if (isReadOnly.value) return
  task.status = getNextStatus(task.status || 'todo')
}

const startTaskEditInModal = (task) => {
  if (isReadOnly.value) return
  if (editingBlock.value.tasks) {
    editingBlock.value.tasks.forEach(t => {
      if (t.id !== task.id) {
        t.isEditingInModal = false
        delete t.editValue
      }
    })
  }
  
  task.isEditingInModal = true
  task.editValue = task.title
  
  setTimeout(() => {
    const inputs = document.querySelectorAll('.modal-task-input')
    if (inputs.length > 0) {
      inputs[inputs.length - 1].focus()
    }
  }, 50)
}

const saveTaskEditInModal = (task) => {
  if (isReadOnly.value) return
  if (!task.editValue || task.editValue.trim() === '') {
    task.isEditingInModal = false
    delete task.editValue
    return
  }
  
  task.title = task.editValue.trim()
  task.isEditingInModal = false
  delete task.editValue
}

const cancelTaskEditInModal = (task) => {
  if (isReadOnly.value) return
  task.isEditingInModal = false
  delete task.editValue
}

const deleteTaskInModal = (task) => {
  if (isReadOnly.value) return
  if (!editingBlock.value.tasks) return
  if (taskEditorTaskId.value === task.id) {
    taskEditorTaskId.value = null
  }
  const index = editingBlock.value.tasks.findIndex(t => t.id === task.id)
  if (index === -1) return
  editingBlock.value.tasks.splice(index, 1)
  editingBlock.value.tasks = removePredecessorIdFromAllTasks(
    editingBlock.value.tasks,
    task.id
  )
}

const getTotalTasksEffort = () => {
  if (!editingBlock.value.tasks || editingBlock.value.tasks.length === 0) return 0
  return editingBlock.value.tasks.reduce((sum, task) => sum + (task.effort || 0), 0)
}

// Основные действия модалки: сохранить/удалить/закрыть + pointer-логика оверлея.
const handleSave = () => {
  if (isReadOnly.value) return
  const block = JSON.parse(JSON.stringify(editingBlock.value))
  if (block.tasks?.length) {
    block.tasks = block.tasks.map((t) => ({
      ...t,
      linkUrl: normalizeLinkUrl(t.linkUrl),
      linkNote: typeof t.linkNote === 'string' ? t.linkNote.trim() : '',
      ...normalizeTaskDateRange(t.startDate, t.releaseDate),
      effort: Math.max(0, Number(t.effort) || 0)
    }))
  }
  taskEditorTaskId.value = null
  emit('save', block)
}

const handleDelete = () => {
  if (isReadOnly.value) return
  if (editingBlock.value && editingBlock.value.id) {
    // Убираем confirm
    emit('delete', editingBlock.value.id)
  }
}

const onOverlayPointerDown = (event) => {
  overlayPointerState.value = {
    active: true,
    pointerId: event.pointerId,
    startX: event.clientX,
    startY: event.clientY,
    moved: false
  }
}

const onOverlayPointerMove = (event) => {
  const state = overlayPointerState.value
  if (!state.active || state.pointerId !== event.pointerId) return
  const dx = Math.abs(event.clientX - state.startX)
  const dy = Math.abs(event.clientY - state.startY)
  if (dx > 4 || dy > 4) {
    state.moved = true
  }
}

const onOverlayPointerUp = (event) => {
  const state = overlayPointerState.value
  if (!state.active || state.pointerId !== event.pointerId) return
  const shouldClose = !state.moved
  overlayPointerState.value = {
    active: false,
    pointerId: null,
    startX: 0,
    startY: 0,
    moved: false
  }
  if (shouldClose) handleClose()
}

const onOverlayPointerCancel = () => {
  overlayPointerState.value = {
    active: false,
    pointerId: null,
    startX: 0,
    startY: 0,
    moved: false
  }
}

const handleClose = () => {
  taskEditorTaskId.value = null
  emit('close')
}
</script>

<style scoped>
.modal-overlay {
  position: fixed;
  inset: 0;
  background: rgba(15, 23, 42, 0.45);
  backdrop-filter: blur(4px);
  display: flex;
  justify-content: center;
  align-items: center;
  z-index: 2000;
  padding: 24px;
}

.modal {
  display: flex;
  flex-direction: column;
  width: min(80vw, 1280px);
  height: min(90vh, 920px);
  background: #fff;
  border: 1px solid #e2e8f0;
  border-radius: 12px;
  overflow: hidden;
  box-shadow: 0 20px 48px rgba(15, 23, 42, 0.18);
  font-family: Inter, system-ui, -apple-system, 'Segoe UI', Roboto, Arial, sans-serif;
}

.modal-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  flex-shrink: 0;
  padding: 16px 24px;
  border-bottom: 1px solid #e2e8f0;
}

.modal-header h3 {
  margin: 0;
  font-size: 1rem;
  font-weight: 500;
  color: #0f172a;
}
.close-btn {
  width: 32px;
  height: 32px;
  background: none;
  border: none;
  border-radius: 8px;
  font-size: 1.4rem;
  line-height: 1;
  cursor: pointer;
  color: #64748b;
}

.close-btn:hover {
  color: #ef4444;
  background: #f8fafc;
}

.modal-two-columns {
  display: grid;
  grid-template-columns: minmax(320px, 1fr) minmax(320px, 1fr);
  flex: 1;
  min-height: 0;
  overflow: hidden;
}

.modal-left,
.modal-right {
  min-width: 0;
  min-height: 0;
  overflow: auto;
  display: flex;
  flex-direction: column;
}

.modal-left {
  padding: 16px 24px;
  overflow-x: hidden;
}

.modal-right {
  padding: 24px;
  border-left: 1px solid #e2e8f0;
}

.form-group {
  margin-bottom: 16px;
}

.form-label-row {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 8px;
  margin-bottom: 6px;
}

.form-label-row label {
  margin-bottom: 0;
}

.form-group label,
.modal-task-link-label {
  display: block;
  font-size: 0.9rem;
  font-weight: 600;
  color: #64748b;
  margin-bottom: 6px;
}

.stage-name-input {
  width: 100%;
  box-sizing: border-box;
  border: none;
  background: transparent;
  padding: 4px 2px;
  font-size: 1.5rem;
  font-weight: 600;
  line-height: 1.3;
  color: #0f172a;
  resize: none;
  font-family: inherit;
}

.stage-name-input:focus {
  outline: none;
}

.stage-description-input {
  width: 100%;
  box-sizing: border-box;
  min-height: 160px;
  padding: 12px;
  border: 1px solid #e2e8f0;
  border-radius: 8px;
  font-size: 0.9rem;
  font-family: inherit;
  resize: vertical;
}

.icon-btn {
  width: 28px;
  height: 28px;
  border: none;
  border-radius: 6px;
  background: transparent;
  color: #64748b;
  cursor: pointer;
  display: inline-flex;
  align-items: center;
  justify-content: center;
}

.icon-btn:hover:not(:disabled) {
  background: #f1f5f9;
  color: #0f172a;
}

.icon-btn:disabled {
  opacity: 0.4;
  cursor: default;
}

.form-group input,
.form-group select,
.form-group textarea:not(.stage-name-input) {
  display: block;
  width: 100%;
  max-width: 100%;
  box-sizing: border-box;
  padding: 8px 12px;
  border: 1px solid #e2e8f0;
  border-radius: 8px;
  font-size: 0.9rem;
  font-family: inherit;
  transition: border-color 0.2s;
}

.form-group .stage-full-input {
  display: block;
  width: 100%;
  max-width: 100%;
  box-sizing: border-box;
}

.form-group input:focus,
.form-group textarea:not(.stage-name-input):focus {
  outline: none;
  border-color: #3b82f6;
  box-shadow: 0 0 0 3px rgba(59, 130, 246, 0.1);
}

.form-row {
  display: grid;
  grid-template-columns: minmax(0, 1fr) minmax(0, 1fr);
  gap: 10px;
}

.form-row .form-group {
  min-width: 0;
}

.form-row .form-group input[type="date"] {
  width: 100%;
  max-width: 100%;
  padding: 6px 28px 6px 8px;
  font-size: 0.78rem;
  line-height: 1.2;
  box-sizing: border-box;
}

.effort-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  margin-bottom: 8px;
}

.effort-controls {
  display: inline-flex;
  align-items: center;
  gap: 8px;
}

.effort-inline-input {
  width: 54px;
  min-width: 54px;
  max-width: 54px;
  box-sizing: border-box;
  padding: 0;
  font-size: 0.82rem;
  text-align: right;
  border: 1px solid #fdba74;
  border-radius: 6px;
  color: #f97316;
  font-weight: 600;
  background: #fff7ed;
  -moz-appearance: textfield;
}

.effort-inline-input::-webkit-outer-spin-button,
.effort-inline-input::-webkit-inner-spin-button {
  -webkit-appearance: none;
  margin: 0;
}

.effort-inline-input:focus {
  border-color: #fb923c;
  box-shadow: 0 0 0 2px rgba(249, 115, 22, 0.18);
}

.effort-value {
  font-weight: 600;
  color: #f97316;
  min-width: 54px;
  text-align: right;
}

.effort-value-editable {
  cursor: text;
  border-bottom: 1px dashed rgba(249, 115, 22, 0.5);
}

.effort-value-editable:hover {
  color: #ea580c;
}

.form-group input.effort-range {
  width: 100%;
  height: 8px;
  margin: 0;
  padding: 0;
  position: absolute;
  inset: 0;
  -webkit-appearance: none;
  appearance: none;
  background: transparent !important;
  z-index: 2;
  cursor: pointer;
  outline: none !important;
  border: none !important;
  border-radius: 0 !important;
  box-shadow: none !important;
  opacity: 1;
}
.form-group input.effort-range:focus,
.form-group input.effort-range:focus-visible {
  outline: none !important;
  border: none !important;
  box-shadow: none !important;
}
.effort-range::-webkit-slider-runnable-track {
  height: 8px;
  background: transparent;
  border: none;
}
.effort-range::-moz-range-track {
  height: 8px;
  background: transparent;
  border: none;
}
.effort-range::-webkit-slider-thumb {
  -webkit-appearance: none;
  width: 15px;
  height: 15px;
  border-radius: 50%;
  background: rgba(15, 23, 42, 0.55);
  border: 1px solid rgba(255, 255, 255, 0.78);
  box-shadow: 0 0 0 1px rgba(15, 23, 42, 0.12);
  margin-top: -4px;
}
.effort-range::-moz-range-thumb {
  width: 15px;
  height: 15px;
  border-radius: 50%;
  background: rgba(15, 23, 42, 0.55);
  border: 1px solid rgba(255, 255, 255, 0.78);
  box-shadow: 0 0 0 1px rgba(15, 23, 42, 0.12);
}
.effort-gradient-wrap {
  margin-top: 8px;
  position: relative;
}
.effort-gradient-track {
  width: 100%;
  height: 8px;
  border-radius: 999px;
  background: linear-gradient(90deg, #22c55e 0%, #eab308 55%, #ef4444 100%);
}
.effort-gradient-labels {
  margin-top: 6px;
  display: flex;
  justify-content: space-between;
  font-size: 0.68rem;
  color: #64748b;
}

.tasks-header-modal {
  display: flex;
  justify-content: space-between;
  align-items: center;
  gap: 12px;
  margin-bottom: 12px;
}

.tasks-header-modal label {
  font-size: 0.9rem;
  font-weight: 600;
  color: #64748b;
}

.btn-add-task-modal {
  background: #fff;
  color: #2563eb;
  border: 1px solid #93c5fd;
  padding: 6px 12px;
  border-radius: 8px;
  font-size: 0.8rem;
  font-weight: 600;
  cursor: pointer;
}

.btn-add-task-modal:hover {
  background: #eff6ff;
}

.modal-tasks-list {
  flex: 1;
  min-height: 0;
  overflow-y: auto;
}

.modal-tasks-list.is-empty {
  min-height: 48px;
}

.modal-task-wrap {
  position: relative;
}

.modal-task-wrap + .modal-task-wrap {
  box-shadow: inset 0 1px 0 #e2e8f0;
}

.modal-task-item {
  display: flex;
  align-items: center;
  gap: 12px;
  min-width: 0;
  padding: 10px 8px;
  border-radius: 8px;
  cursor: pointer;
}

.modal-task-item:hover {
  background: #f8fafc;
}

.modal-task-item.is-active {
  background: #eff6ff;
}
.modal-task-item :deep(.app-tooltip-trigger.is-fill) {
  flex: 1 1 auto;
  min-width: 0;
}

.modal-task-status {
  width: 28px;
  height: 28px;
  display: flex;
  align-items: center;
  justify-content: center;
  cursor: pointer;
  border-radius: 14px;
  flex-shrink: 0;
  transition: transform 0.2s;
}

.modal-task-status:hover {
  background: #e2e8f0;
  transform: scale(1.1);
}

.modal-task-content {
  flex: 1;
  min-width: 0;
}

.modal-task-info {
  display: flex;
  align-items: center;
  gap: 12px;
  flex-wrap: wrap;
}

.modal-task-title {
  display: block;
  min-width: 0;
  width: 100%;
  font-size: 0.9rem;
  color: #0f172a;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.modal-task-meta {
  display: inline-flex;
  align-items: center;
  gap: 8px;
  flex-shrink: 0;
  margin-left: auto;
}

.modal-task-link {
  width: 24px;
  height: 24px;
  border: none;
  background: transparent;
  border-radius: 6px;
  display: inline-flex;
  align-items: center;
  justify-content: center;
  cursor: pointer;
  padding: 0;
}

.modal-task-link:hover {
  background: rgba(37, 99, 235, 0.08);
}

.modal-task-link-icon {
  width: 16px;
  height: 16px;
  display: block;
}

.task-status {
  flex-shrink: 0;
  box-sizing: border-box;
  width: 16px;
  height: 16px;
  min-width: 16px;
  margin: 0;
  padding: 0;
  border: 2px solid #94a3b8;
  border-radius: 50%;
  background: transparent;
  appearance: none;
  cursor: pointer;
}
.task-status:disabled { cursor: default; }
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

.modal-task-effort {
  display: flex;
  align-items: center;
  gap: 4px;
  background: #f1f5f9;
  padding: 4px 8px;
  border-radius: 20px;
}

.task-effort-input {
  width: 50px;
  padding: 4px 6px;
  border: none;
  background: transparent;
  font-size: 0.75rem;
  font-weight: 500;
  color: #f97316;
  text-align: right;
  outline: none;
}

.task-effort-value {
  font-size: 0.85rem;
  font-weight: 500;
  color: #64748b;
  white-space: nowrap;
}

.modal-task-deps {
  margin-top: 8px;
  padding: 6px 8px;
  background: #f8fafc;
  border-radius: 8px;
  border: 1px solid #e2e8f0;
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: 6px 10px;
  font-size: 0.72rem;
  color: #475569;
}

.deps-label {
  font-weight: 600;
  color: #64748b;
  margin-right: 4px;
}

.dep-checkbox {
  display: inline-flex;
  align-items: center;
  gap: 4px;
  cursor: pointer;
  user-select: none;
}

.dep-checkbox input {
  accent-color: #94a3b8;
}

.dep-checkbox-title {
  max-width: 140px;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.modal-task-edit-area {
  width: 100%;
}

.modal-task-input {
  width: 100%;
  padding: 8px 10px;
  border: 1px solid #3b82f6;
  border-radius: 8px;
  font-size: 0.85rem;
  outline: none;
  background: white;
  resize: vertical;
  font-family: inherit;
}

.modal-task-actions {
  display: flex;
  gap: 6px;
  flex-shrink: 0;
  opacity: 0;
  transition: opacity 0.2s;
}

.modal-task-item:hover .modal-task-actions {
  opacity: 1;
}

.modal-task-link,
.modal-task-edit,
.modal-task-delete {
  width: 28px;
  height: 28px;
  border: none;
  background: transparent;
  font-size: 0.8rem;
  cursor: pointer;
  border-radius: 6px;
  display: flex;
  align-items: center;
  justify-content: center;
  transition: all 0.2s;
}

.modal-task-link:hover {
  background: #e0f2fe;
  color: #0369a1;
}

.modal-task-link.active {
  background: #bae6fd;
  color: #0c4a6e;
}

.modal-task-edit:hover {
  background: transparent;
  color: inherit;
}

.modal-task-edit.active {
  background: transparent;
  color: inherit;
}

.modal-task-edit {
  width: auto;
  height: auto;
  padding: 0;
  border-radius: 0;
}

.modal-task-edit-icon {
  width: 14px;
  height: 14px;
  display: block;
  transition: transform 0.14s ease;
}

.modal-task-edit:hover .modal-task-edit-icon,
.modal-task-edit.active .modal-task-edit-icon {
  transform: scale(1.08);
}

.modal-task-delete:hover {
  background: #fee2e2;
  color: #ef4444;
}

.modal-task-editor-panel {
  display: flex;
  flex-direction: column;
  gap: 8px;
  margin: 4px 0 12px;
  padding: 16px;
  border: 1px solid #e2e8f0;
  border-radius: 8px;
  background: #fff;
  box-shadow:
    0 8px 24px rgba(15, 23, 42, 0.12),
    0 2px 8px rgba(15, 23, 42, 0.06);
}

.modal-task-dates-row {
  margin-top: 2px;
}

.modal-task-date-label {
  margin-top: 0;
}

.modal-task-date-label input {
  margin-top: 4px;
}

.modal-task-link-row {
  display: flex;
  align-items: center;
  gap: 8px;
}

.modal-task-link-label {
  margin-top: 4px;
}

.modal-task-link-label:first-child {
  margin-top: 0;
}

.modal-task-link-field {
  width: 100%;
  padding: 8px 12px;
  border: 1px solid #e2e8f0;
  border-radius: 8px;
  font-size: 0.9rem;
  box-sizing: border-box;
  font-family: inherit;
}

.btn-clear-link {
  width: 28px;
  height: 28px;
  border: 1px solid #fecaca;
  border-radius: 8px;
  background: #fff1f2;
  color: #ef4444;
  font-size: 1rem;
  line-height: 1;
  cursor: pointer;
}

.btn-clear-link:hover:not(:disabled) {
  background: #ffe4e6;
}

.btn-clear-link:disabled {
  opacity: 0.45;
  cursor: not-allowed;
}

.modal-task-link-field:focus {
  outline: none;
  border-color: #3b82f6;
  box-shadow: 0 0 0 3px rgba(59, 130, 246, 0.1);
}

.modal-task-link-actions {
  margin-top: 10px;
}

.modal-task-editor-actions {
  display: flex;
  justify-content: space-between;
  align-items: center;
  gap: 8px;
  flex-wrap: wrap;
  margin-top: 8px;
}

.btn-clear-link-inline {
  border-color: #fecaca;
  color: #b91c1c;
  background: #fff1f2;
}

.btn-clear-link-inline:hover {
  background: #ffe4e6;
  color: #991b1b;
}

.btn-open-link {
  padding: 6px 12px;
  font-size: 0.75rem;
  font-weight: 600;
  border-radius: 8px;
  border: 1px solid #3b82f6;
  background: #eff6ff;
  color: #1d4ed8;
  cursor: pointer;
}

.btn-open-link.btn-ghost {
  border-color: #cbd5e1;
  color: #475569;
  background: #ffffff;
}

.btn-open-link.btn-clear {
  border-color: #fecaca;
  color: #b91c1c;
  background: #fff1f2;
}

.btn-open-link:hover:not(:disabled) {
  background: #dbeafe;
}

.btn-open-link.btn-ghost:hover:not(:disabled) {
  background: #f8fafc;
}

.btn-open-link.btn-clear:hover:not(:disabled) {
  background: #ffe4e6;
}

.btn-open-link:disabled {
  opacity: 0.45;
  cursor: not-allowed;
}

.modal-tasks-empty {
  padding: 12px 8px;
  color: #64748b;
  font-size: 0.9rem;
}

.empty-hint {
  font-size: 0.7rem;
  opacity: 0.7;
}

.tasks-total-effort {
  margin-top: 8px;
  padding: 16px 8px 0;
  border-top: 1px solid #e2e8f0;
  display: flex;
  justify-content: flex-end;
  align-items: center;
  gap: 8px;
  font-size: 0.9rem;
}

.total-label {
  color: #64748b;
}

.total-value {
  color: #2563eb;
  font-weight: 500;
}

.modal-footer {
  display: flex;
  justify-content: space-between;
  align-items: center;
  flex-shrink: 0;
  padding: 16px 24px;
  border-top: 1px solid #e2e8f0;
  gap: 12px;
  flex-wrap: wrap;
}

.modal-task-name-field {
  resize: vertical;
  min-height: 48px;
}

@media (max-width: 860px) {
  .modal {
    width: 100%;
    height: 100%;
    max-height: none;
    border-radius: 0;
  }
  .modal-two-columns {
    grid-template-columns: 1fr;
    overflow: auto;
  }
  .modal-right {
    border-left: none;
    border-top: 1px solid #e2e8f0;
  }
}

.btn {
  padding: 8px 20px;
  font-size: 0.85rem;
  font-weight: 500;
  border-radius: 8px;
  cursor: pointer;
  border: none;
  transition: all 0.2s;
}

.btn-danger {
  background: #fee2e2;
  color: #ef4444;
  border: 1px solid #fecaca;
}

.btn-danger:hover {
  background: #fecaca;
  color: #dc2626;
}

.btn-text {
  background: transparent;
  color: #64748b;
  border: 1px solid #e2e8f0;
}

.btn-text:hover {
  background: #f1f5f9;
  color: #1e293b;
}

.btn-secondary {
  background: #3b82f6;
  color: white;
}

.btn-secondary:hover {
  background: #2563eb;
}

.footer-actions {
  display: flex;
  gap: 12px;
}
</style>