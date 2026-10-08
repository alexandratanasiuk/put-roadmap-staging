<template>
  <div
    v-if="block && task"
    class="task-card-overlay"
    @pointerdown.self="onOverlayPointerDown"
    @pointermove.self="onOverlayPointerMove"
    @pointerup.self="onOverlayPointerUp"
    @pointercancel.self="onOverlayPointerCancel"
  >
    <div class="task-card-modal" @click.stop>
      <div class="task-card-modal-header">
        <h4 class="task-card-title">Редактирование элемента</h4>
        <button type="button" class="task-card-close" aria-label="Закрыть" @click="emit('close')">×</button>
      </div>

      <div class="form-group">
        <textarea
          v-model="draft.title"
          class="task-card-name"
          rows="2"
          placeholder="Название элемента"
        ></textarea>
      </div>

      <div class="form-group">
        <label>Ссылка</label>
        <div class="task-card-link-row">
          <input
            v-model="draft.linkUrl"
            type="url"
            class="task-card-input"
            placeholder="https://..."
          >
          <Tooltip label="Открыть ссылку">
            <button
              type="button"
              class="task-card-link-btn"
              :disabled="!normalizeLinkUrl(draft.linkUrl)"
              aria-label="Открыть ссылку"
              @click="openDraftLink"
            >
              <img :src="linkIcon" alt="" class="task-card-link-btn-icon">
            </button>
          </Tooltip>
          <button
            v-if="draft.linkUrl"
            type="button"
            class="task-card-clear"
            aria-label="Очистить ссылку"
            @click="clearLink"
          >×</button>
        </div>
      </div>

      <div class="form-row">
        <div class="form-group">
          <label>Дата начала</label>
          <input
            v-model="draft.startDate"
            type="date"
            class="task-card-input"
            :min="startMinDate"
            :max="startMaxDate"
          >
        </div>
        <div class="form-group">
          <label>Дата окончания</label>
          <input
            v-model="draft.releaseDate"
            type="date"
            class="task-card-input"
            :min="endMinDate"
            :max="endMaxDate"
          >
        </div>
      </div>

      <div class="form-group">
        <label>Трудозатраты, ч</label>
        <input
          v-model.number="draft.effort"
          type="number"
          min="0"
          step="1"
          class="task-card-input"
          placeholder="0"
        >
      </div>

      <div class="task-card-footer">
        <button type="button" class="btn btn-danger btn-delete-left" @click="emit('delete')">Удалить</button>
        <div class="task-card-footer-actions">
          <button type="button" class="btn btn-text" @click="emit('close')">Отмена</button>
          <button type="button" class="btn btn-secondary" @click="save">Сохранить</button>
        </div>
      </div>
    </div>
  </div>
</template>

<script setup>
import { computed, ref, watch } from 'vue'
import linkIcon from '@/assets/link-icon.png'
import Tooltip from './Tooltip.vue'

// Карточка получает текущий этап и выбранную задачу для редактирования.
const props = defineProps({
  block: { type: Object, default: null },
  task: { type: Object, default: null }
})

// close — закрыть без сохранения, save — применить изменения, delete — удалить задачу.
const emit = defineEmits(['close', 'save', 'delete'])

// Локальный draft формы: редактируем его, а наверх отправляем только на Save.
const draft = ref({
  title: '',
  linkUrl: '',
  linkNote: '',
  startDate: '',
  releaseDate: '',
  effort: 0
})

// Нужен, чтобы клик по затемненному фону закрывал модалку,
// а drag/свайп по оверлею случайно не закрывал.
const overlayPointerState = ref({
  active: false,
  pointerId: null,
  startX: 0,
  startY: 0,
  moved: false
})

// Приводит дату к безопасному формату yyyy-mm-dd.
const normalizeDateValue = (value) => {
  if (!value || typeof value !== 'string') return ''
  const trimmed = value.trim()
  return /^\d{4}-\d{2}-\d{2}$/.test(trimmed) ? trimmed : ''
}

// Нормализация URL: если нет протокола, добавляем https://.
const normalizeLinkUrl = (raw) => {
  if (!raw || typeof raw !== 'string') return ''
  const trimmed = raw.trim()
  if (!trimmed) return ''
  if (/^https?:\/\//i.test(trimmed)) return trimmed
  return `https://${trimmed}`
}

// Нормализует даты задачи и не дает endDate быть раньше startDate.
const normalizeTaskDates = (startDateRaw, releaseDateRaw) => {
  let startDate = normalizeDateValue(startDateRaw)
  let releaseDate = normalizeDateValue(releaseDateRaw)

  if (startDate && releaseDate && startDate > releaseDate) releaseDate = startDate

  return { startDate, releaseDate }
}

// Ограничения date-input: здесь только внутренние ограничения между start/end.
const startMinDate = computed(() => '')
const startMaxDate = computed(() => {
  const draftEnd = normalizeDateValue(draft.value.releaseDate)
  return draftEnd || ''
})
const endMinDate = computed(() => {
  const draftStart = normalizeDateValue(draft.value.startDate)
  return draftStart || ''
})
const endMaxDate = computed(() => '')

// При смене block/task пересобираем draft из актуальных данных.
watch(
  () => [props.block, props.task],
  () => {
    if (!props.task) return
    const { startDate, releaseDate } = normalizeTaskDates(props.task.startDate, props.task.releaseDate)
    draft.value = {
      title: props.task.title || '',
      linkUrl: props.task.linkUrl || '',
      linkNote: typeof props.task.linkNote === 'string' ? props.task.linkNote : '',
      startDate,
      releaseDate,
      effort: Number.isFinite(Number(props.task.effort)) ? Number(props.task.effort) : 0
    }
  },
  { immediate: true, deep: true }
)

// Быстрые действия над ссылкой.
const clearLink = () => {
  draft.value.linkUrl = ''
}

const openDraftLink = () => {
  const normalized = normalizeLinkUrl(draft.value.linkUrl)
  if (!normalized) return
  window.open(normalized, '_blank', 'noopener,noreferrer')
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

// Фиксируем, что курсор сдвинулся: это уже не "простой клик" для закрытия.
const onOverlayPointerMove = (event) => {
  const state = overlayPointerState.value
  if (!state.active || state.pointerId !== event.pointerId) return
  const dx = Math.abs(event.clientX - state.startX)
  const dy = Math.abs(event.clientY - state.startY)
  if (dx > 4 || dy > 4) state.moved = true
}

// Закрываем модалку только если пользователь действительно кликнул по оверлею без движения.
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
  if (shouldClose) emit('close')
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

const save = () => {
  // На сохранение отправляем уже нормализованные значения.
  const { startDate, releaseDate } = normalizeTaskDates(draft.value.startDate, draft.value.releaseDate)
  const title = String(draft.value.title || '').trim()
  emit('save', {
    title: title || String(props.task?.title || '').trim() || 'Новая задача',
    linkUrl: normalizeLinkUrl(draft.value.linkUrl),
    linkNote: String(draft.value.linkNote || '').trim(),
    startDate,
    releaseDate,
    effort: Math.max(0, Number(draft.value.effort) || 0)
  })
}
</script>

<style scoped>
.task-card-overlay {
  position: fixed;
  inset: 0;
  background: rgba(0, 0, 0, 0.5);
  backdrop-filter: blur(4px);
  z-index: 2200;
  display: flex;
  align-items: center;
  justify-content: center;
  padding: 24px;
}
.task-card-modal {
  width: min(560px, 100%);
  background: #ffffff;
  border: 1px solid #e2e8f0;
  border-radius: 12px;
  box-shadow: 0 20px 48px rgba(15, 23, 42, 0.18);
  padding: 0 0 8px;
  font-family: Inter, system-ui, -apple-system, 'Segoe UI', Roboto, Arial, sans-serif;
}
.task-card-modal-header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  margin-bottom: 8px;
  padding: 16px 24px 12px;
  border-bottom: 1px solid #e2e8f0;
}
.task-card-modal-header h4 {
  margin: 0;
  font-size: 1rem;
  font-weight: 500;
  color: #0f172a;
}
.task-card-title {
  display: inline-flex;
  align-items: center;
  gap: 8px;
}
.task-card-modal > .form-group,
.task-card-modal > .form-row {
  padding: 0 24px;
}
.task-card-close {
  width: 28px;
  height: 28px;
  border: none;
  border-radius: 7px;
  background: transparent;
  color: #64748b;
  font-size: 1.1rem;
  cursor: pointer;
}
.task-card-close:hover {
  color: #ef4444;
}
.form-group {
  margin-bottom: 12px;
}
.form-group label {
  display: block;
  font-size: 0.9rem;
  font-weight: 600;
  color: #64748b;
  margin-bottom: 6px;
}
.task-card-name {
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
.task-card-name:focus {
  outline: none;
}
.task-card-input {
  width: 100%;
  box-sizing: border-box;
  border: 1px solid #cbd5e1;
  border-radius: 8px;
  padding: 8px 12px;
  font-size: 0.9rem;
  font-family: inherit;
  margin-bottom: 0;
}
.task-card-link-row {
  display: flex;
  align-items: center;
  gap: 8px;
}
.task-card-link-btn {
  width: 40px;
  height: 40px;
  flex-shrink: 0;
  border: 1px solid #cbd5e1;
  border-radius: 8px;
  background: #ffffff;
  display: inline-flex;
  align-items: center;
  justify-content: center;
  cursor: pointer;
  transition: background 0.15s ease, border-color 0.15s ease;
}
.task-card-link-btn:hover:not(:disabled) {
  background: #f8fafc;
  border-color: #94a3b8;
}
.task-card-link-btn:disabled {
  opacity: 0.45;
  cursor: not-allowed;
}
.task-card-link-btn-icon {
  width: 18px;
  height: 18px;
  display: block;
}
.task-card-textarea {
  width: 100%;
  box-sizing: border-box;
  border: 1px solid #cbd5e1;
  border-radius: 8px;
  padding: 8px 12px;
  font-size: 0.9rem;
  font-family: inherit;
  resize: vertical;
}
.task-card-input:focus {
  outline: none;
  border-color: #3b82f6;
  box-shadow: 0 0 0 3px rgba(59, 130, 246, 0.1);
}
.task-card-textarea:focus {
  outline: none;
  border-color: #3b82f6;
  box-shadow: 0 0 0 3px rgba(59, 130, 246, 0.1);
}
.form-row {
  display: grid;
  grid-template-columns: minmax(0, 1fr) minmax(0, 1fr);
  gap: 10px;
}
.task-card-clear {
  width: 32px;
  height: 40px;
  flex-shrink: 0;
  border: none;
  background: transparent;
  color: #64748b;
  font-size: 1.2rem;
  cursor: pointer;
  border-radius: 8px;
}
.task-card-clear:hover {
  background: #f1f5f9;
  color: #0f172a;
}
.task-card-footer {
  margin-top: 10px;
  padding: 16px 24px 16px;
  border-top: 1px solid #e2e8f0;
  display: flex;
  justify-content: space-between;
  align-items: center;
  gap: 10px;
  flex-wrap: wrap;
}
.task-card-footer-actions {
  display: flex;
  gap: 10px;
}
.btn {
  border: 1px solid #3b82f6;
  background: #eff6ff;
  color: #1d4ed8;
  border-radius: 8px;
  font-size: 0.8rem;
  font-weight: 600;
  padding: 7px 12px;
  cursor: pointer;
}
.btn:hover {
  background: #dbeafe;
}
.btn-text {
  border-color: #cbd5e1;
  background: #ffffff;
  color: #475569;
}
.btn-text:hover {
  background: #f8fafc;
}
.btn-clear-link {
  border-color: #cbd5e1;
  color: #475569;
  background: #ffffff;
}
.btn-clear-link:hover {
  background: #f8fafc;
}
.btn-secondary {
  border-color: #3b82f6;
  background: #3b82f6;
  color: #ffffff;
}
.btn-secondary:hover {
  background: #2563eb;
  border-color: #2563eb;
}
.btn-danger {
  border-color: #fecaca;
  background: #fff1f2;
  color: #b91c1c;
}
.btn-danger:hover {
  background: #ffe4e6;
}
.btn-delete-left {
  margin-right: auto;
}
</style>
