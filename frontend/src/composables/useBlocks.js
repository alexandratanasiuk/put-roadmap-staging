import { ref, computed } from 'vue'
import axios from 'axios'
import { useAuth } from './useAuth'
import { useProjects } from './useProjects'
import { normalizeTasksArray } from '@/utils/taskModel'

// Shared singleton state for all composable consumers.
const blocks = ref([])
const isLoadingBlocks = ref(false)

export function useBlocks() {
  // Зависимости: auth-контекст и текущий активный проект.
  const { isAuthenticated, handleLogout, API_URL, isReadOnly } = useAuth()
  const { activeProjectId } = useProjects()
  const apiPath = (path) => `${API_URL}${path.startsWith('/') ? path : `/${path}`}`
  const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms))

  // Классификация сетевых ошибок для retry-логики.
  const isTransientNetworkError = (error) => {
    if (!error) return false
    if (error.code === 'ECONNABORTED') return true
    if (error.code === 'ETIMEDOUT') return true
    if (error.code === 'ERR_NETWORK') return true
    return !error.response
  }

  // PUT c повторной попыткой при временных сетевых сбоях.
  const putWithRetry = async (url, payload, options = {}) => {
    const attempts = options.attempts ?? 3
    const timeoutMs = options.timeoutMs ?? 15000
    let lastError = null
    for (let attempt = 1; attempt <= attempts; attempt += 1) {
      try {
        return await axios.put(url, payload, { timeout: timeoutMs })
      } catch (error) {
        lastError = error
        if (!isTransientNetworkError(error) || attempt >= attempts) {
          throw error
        }
        await sleep(350 * attempt)
      }
    }
    throw lastError
  }

  // Проверяет, относится ли этап к текущему выбранному проекту.
  const belongsToActiveProject = (blockLike) => {
    const currentProjectId = String(activeProjectId.value || '')
    const blockProjectId = String(blockLike?.projectId || '')
    if (!currentProjectId) return false
    return blockProjectId === currentProjectId
  }

  // Загружает этапы выбранного проекта и нормализует массив задач.
  const loadBlocks = async () => {
    if (!isAuthenticated.value) return
    if (isLoadingBlocks.value) return
    if (!activeProjectId.value) {
      blocks.value = []
      return { success: true, blocks: [] }
    }
    
    isLoadingBlocks.value = true
    try {
      const response = await axios.get(apiPath('/blocks'), {
        params: { projectId: activeProjectId.value }
      })
      const payload = response.data
      const list = Array.isArray(payload)
        ? payload
        : (Array.isArray(payload?.blocks) ? payload.blocks : [])
      blocks.value = list.map((b) => ({
        ...b,
        tasks: normalizeTasksArray(b.tasks),
        stagePredecessorIds: Array.isArray(b.stagePredecessorIds) ? b.stagePredecessorIds : [],
        stageDependencies: Array.isArray(b.stageDependencies) ? b.stageDependencies : [],
        completed: b.stageStatus === 'done' || Boolean(b.completed),
        isOverdue: Boolean(b.isOverdue)
      }))
      console.log('✅ Блоки загружены:', blocks.value.length)
      return { success: true, blocks: blocks.value }
    } catch (error) {
      console.error('❌ Ошибка загрузки:', error)
      if (error.response?.status === 401) {
        handleLogout()
      }
      return { success: false, error }
    } finally {
      isLoadingBlocks.value = false
    }
  }

  // Создание нового этапа с дефолтными датами и параметрами.
  const createNewBlock = async () => {
  if (!isAuthenticated.value) {
    return { success: false, message: 'Требуется авторизация' }
  }
  if (isReadOnly.value) {
    return { success: false, message: 'Режим только просмотра' }
  }
  if (!activeProjectId.value) {
    return { success: false, message: 'Сначала выберите проект' }
  }

  try {
    const response = await axios.post(apiPath('/blocks'), {
      projectId: activeProjectId.value
    })
    blocks.value.push({
      ...response.data,
      tasks: normalizeTasksArray(response.data.tasks),
      stagePredecessorIds: Array.isArray(response.data.stagePredecessorIds) ? response.data.stagePredecessorIds : [],
      stageDependencies: Array.isArray(response.data.stageDependencies) ? response.data.stageDependencies : []
    })
    
    // ВАЖНО: принудительно обновляем позиции блоков
    forceUpdatePositions()
    
    return { success: true, block: response.data }
  } catch (error) {
    console.error('❌ Ошибка создания:', error)
    return { success: false, message: 'Ошибка создания' }
  }
}

      // Удаляет этап и обновляет локальный список/позиции.
      const deleteBlock = async (id) => {
        try {
          if (isReadOnly.value) {
            return { success: false, message: 'Режим только просмотра' }
          }
          console.log('🗑️ Удаляем блок с ID:', id)
          await axios.delete(apiPath(`/blocks/${id}`))
          blocks.value = blocks.value.filter(b => b.id !== id)
          forceUpdatePositions()
          return { success: true, message: '✅ Этап удален' }
        } catch (error) {
          console.error('❌ Ошибка удаления:', error)
          return { success: false, message: '❌ Ошибка удаления' }
        }
      }

  const stageFieldsFrom = (blockLike) => ({
    title: blockLike?.title,
    description: blockLike?.description,
    startDate: blockLike?.startDate,
    releaseDate: blockLike?.releaseDate,
    effort: blockLike?.effort,
    completed: blockLike?.completed,
    projectId: blockLike?.projectId
  })

  const applyBlockFromApi = (apiBlock, extras = {}) => {
    if (!apiBlock?.id) return null
    const index = blocks.value.findIndex((b) => b.id === apiBlock.id)
    const prev = index !== -1 ? blocks.value[index] : null
    const merged = {
      ...apiBlock,
      tasks: normalizeTasksArray(apiBlock.tasks),
      completed: apiBlock.stageStatus === 'done',
      isOverdue: Boolean(apiBlock.isOverdue),
      stagePredecessorIds: Array.isArray(apiBlock.stagePredecessorIds)
        ? apiBlock.stagePredecessorIds
        : (extras.stagePredecessorIds ?? prev?.stagePredecessorIds ?? []),
      stageDependencies: Array.isArray(apiBlock.stageDependencies)
        ? apiBlock.stageDependencies
        : (extras.stageDependencies ?? prev?.stageDependencies ?? []),
      stageDependencyMeta: apiBlock.stageDependencyMeta ?? extras.stageDependencyMeta ?? prev?.stageDependencyMeta ?? null
    }
    if (index !== -1) {
      if (belongsToActiveProject(merged)) {
        blocks.value[index] = merged
      } else {
        blocks.value.splice(index, 1)
      }
    }
    return merged
  }

  // Поля этапа — PUT /blocks. Массив задач — PUT /blocks/:id/tasks в таблицы.
  const updateBlock = async (block) => {
    try {
      if (isReadOnly.value) {
        return { success: false, message: 'Режим только просмотра' }
      }
      const extras = {
        stagePredecessorIds: block.stagePredecessorIds,
        stageDependencyMeta: block.stageDependencyMeta
      }
      const stageRes = await putWithRetry(apiPath(`/blocks/${block.id}`), stageFieldsFrom(block))
      let apiBlock = stageRes.data
      if (Array.isArray(block.tasks)) {
        const tasksRes = await putWithRetry(apiPath(`/blocks/${block.id}/tasks`), { tasks: block.tasks })
        apiBlock = tasksRes.data
      }
      const merged = applyBlockFromApi(apiBlock, extras)
      return { success: true, block: merged }
    } catch (error) {
      console.error('Ошибка обновления:', error)
      if (isTransientNetworkError(error)) {
        return { success: false, message: 'Сеть нестабильна. Попробуйте ещё раз.' }
      }
      return { success: false, message: 'Ошибка обновления' }
    }
  }

  const updateStageDependencies = async (blockId, deps) => {
    try {
      if (isReadOnly.value) {
        return { success: false, message: 'Режим только просмотра' }
      }
      const response = await putWithRetry(apiPath(`/blocks/${blockId}/stage-deps`), { deps })
      const merged = applyBlockFromApi(response.data)
      return { success: true, block: merged }
    } catch (error) {
      console.error('Ошибка связей этапов:', error)
      if (isTransientNetworkError(error)) {
        return { success: false, message: 'Сеть нестабильна. Попробуйте ещё раз.' }
      }
      return { success: false, message: error.response?.data?.error || 'Ошибка сохранения связей этапов' }
    }
  }

  const patchStageDepLabel = async (blockId, predecessorId, label) => {
    try {
      if (isReadOnly.value) {
        return { success: false, message: 'Режим только просмотра' }
      }
      const response = await axios.patch(apiPath(`/blocks/${blockId}/stage-deps/${predecessorId}`), label)
      const merged = applyBlockFromApi(response.data)
      return { success: true, block: merged }
    } catch (error) {
      console.error('Ошибка подписи связи этапов:', error)
      return { success: false, message: error.response?.data?.error || 'Ошибка сохранения подписи' }
    }
  }

  const toDateInputValue = (value) => {
    const raw = String(value || '').trim()
    if (/^\d{4}-\d{2}-\d{2}/.test(raw)) return raw.slice(0, 10)
    return ''
  }

  const normalizeStageDatePair = (startDate, releaseDate, changedField) => {
    let start = toDateInputValue(startDate)
    let end = toDateInputValue(releaseDate)
    if (start && end && start > end) {
      if (changedField === 'startDate') end = start
      else if (changedField === 'releaseDate') start = end
      else {
        const swapped = start
        start = end
        end = swapped
      }
    }
    return { startDate: start, releaseDate: end }
  }

  // Частичное обновление дат этапа (начало и/или конец).
  const updateBlockDate = async (block, dates) => {
    try {
      if (isReadOnly.value) {
        return { success: false, error: new Error('read-only') }
      }
      const patch = typeof dates === 'string' ? { releaseDate: dates } : (dates || {})
      const { startDate, releaseDate } = normalizeStageDatePair(
        patch.startDate ?? block.startDate,
        patch.releaseDate ?? block.releaseDate,
        patch.changedField
      )
      const updatedBlock = { ...block, startDate, releaseDate }
      const response = await axios.put(apiPath(`/blocks/${block.id}`), stageFieldsFrom(updatedBlock))
      const merged = applyBlockFromApi(response.data, {
        stagePredecessorIds: updatedBlock.stagePredecessorIds,
        stageDependencyMeta: updatedBlock.stageDependencyMeta
      })
      forceUpdatePositions()
      return { success: true, block: merged }
    } catch (error) {
      console.error('❌ Ошибка при обновлении даты:', error)
      return { success: false, error }
    }
  }

  // Пересчет локальных layout-полей и сортировки задач после мутаций.
const forceUpdatePositions = () => {
  console.log('🔄 forceUpdatePositions called')
  blocks.value = blocks.value.map(block => ({
    ...block,
    positionInMonth: undefined,
    positionInQuarter: undefined,
    tasks: block.tasks
      ? normalizeTasksArray(block.tasks).sort((a, b) => (a.order || 0) - (b.order || 0))
      : []
  }))
  
  // Принудительно вызываем пересчет sortedBlocks в компонентах
  // через nextTick, чтобы Vue успел обновить DOM
  setTimeout(() => {
    console.log('✅ positions updated, blocks count:', blocks.value.length)
  }, 50)
}

  // Агрегаты шапки — те же формулы, что v_project_stats, по computed-полям API.
  const blockTasksTotal = (block) => {
    const n = Number(block?.taskCounts?.total)
    return Number.isFinite(n) ? n : (block?.tasks?.length || 0)
  }
  const blockTasksDone = (block) => {
    const n = Number(block?.taskCounts?.done)
    return Number.isFinite(n) ? n : (block?.tasks || []).filter((t) => t.status === 'done').length
  }

  const completedReleasesCount = computed(() =>
    blocks.value.filter((block) => block.stageStatus === 'done').length
  )

  const inProgressReleasesCount = computed(() =>
    blocks.value.filter((block) => blockTasksTotal(block) > 0 && block.stageStatus !== 'done').length
  )

  const totalTasksCount = computed(() =>
    blocks.value.reduce((sum, block) => sum + blockTasksTotal(block), 0)
  )

  const completedTasksCount = computed(() =>
    blocks.value.reduce((sum, block) => sum + blockTasksDone(block), 0)
  )

  const overallProgress = computed(() => {
    if (totalTasksCount.value === 0) return 0
    return Math.round((completedTasksCount.value / totalTasksCount.value) * 100)
  })

  const totalEffort = computed(() =>
    blocks.value.reduce((sum, block) => sum + (Number(block.effort) || 0), 0)
  )

  const completedEffort = computed(() =>
    blocks.value.reduce((sum, block) => (
      block.stageStatus === 'done' ? sum + (Number(block.effort) || 0) : sum
    ), 0)
  )

  const completedEffortPercent = computed(() => {
    if (totalEffort.value === 0) return 0
    return Math.round((completedEffort.value / totalEffort.value) * 100)
  })

  // Утилиты прогресса этапов/задач. Если API уже отдал computed — берём его.
  const getTaskProgress = (block) => {
    if (Number.isFinite(Number(block?.progressPercent))) return Number(block.progressPercent)
    if (!block.tasks || block.tasks.length === 0) return 0
    const completedTasks = block.tasks.filter(task => task.status === 'done').length
    return Math.round((completedTasks / block.tasks.length) * 100)
  }

  const getCompletedTasksCount = (block) => {
    if (Number.isFinite(Number(block?.taskCounts?.done))) return Number(block.taskCounts.done)
    if (!block.tasks) return 0
    return block.tasks.filter(task => task.status === 'done').length
  }

  /** Есть ли у этапа хотя бы одна задача в статусе «в работе». */
  const blockHasTaskInProgress = (block) => {
    if (Number.isFinite(Number(block?.taskCounts?.progress))) return Number(block.taskCounts.progress) > 0
    if (!block?.tasks?.length) return false
    return block.tasks.some((t) => t.status === 'progress')
  }

  /** Этап начат (есть выполненные или в работе), но не завершён полностью. */
  const blockIsStarted = (block) => {
    if (block?.stageStatus) return block.stageStatus === 'started'
    if (!block?.tasks?.length) return false
    const allDone = block.tasks.every((task) => task.status === 'done')
    if (allDone) return false
    return block.tasks.some((task) => task.status === 'progress' || task.status === 'done')
  }

  // Цвета карточки этапа (как у полосы Ганта: done / active / idle).
  const getBlockBackgroundColor = (block) => {
    if (block?.stageStatus === 'done' || block?.completed) return '#90EE90'
    if (block?.stageStatus === 'started' || blockIsStarted(block)) return '#87CEEB'
    return '#C0C0C0'
  }

  const stageProgressPercent = (block) => {
    if (Number.isFinite(Number(block?.progressPercent))) return Number(block.progressPercent)
    return 0
  }

  const stageTimelineStatus = (block) => {
    if (block?.stageStatus === 'done') return 'done'
    if (block?.stageStatus === 'started') return 'progress'
    return 'todo'
  }

  const getEffortColor = (effort, opacity = 1) => {
    const e = effort || 0
    if (e < 250) return `rgba(34, 197, 94, ${opacity})`
    if (e < 400) return `rgba(234, 179, 8, ${opacity})`
    if (e < 800) return `rgba(249, 115, 22, ${opacity})`
    return `rgba(239, 68, 68, ${opacity})`
  }

  const getPriorityClass = (effort) => {
    const e = effort || 0
    if (e < 40) return 'priority-low'
    if (e < 80) return 'priority-medium'
    if (e < 120) return 'priority-high'
    return 'priority-critical'
  }

  const getPriorityIcon = (effort) => {
    const e = effort || 0
    if (e < 40) return '●'
    if (e < 80) return '◆'
    if (e < 120) return '▲'
    return '❗'
  }

  const getProgressColor = (percent) => {
    if (percent < 30) return '#ef4444'
    if (percent < 70) return '#f97316'
    if (percent < 100) return '#eab308'
    return '#90EE90'
  }

  const calculateBlockHeight = (block) => {
    const tasksCount = Array.isArray(block?.tasks) ? block.tasks.length : 0
    const itemsHeight = tasksCount > 0 ? tasksCount * 28 : 28
    return Math.min(56 + 40 + itemsHeight + 40 + 32, 1200)
  }

  // Получение оригинального блока по ID (для тепловой карты)
  const getOriginalBlock = (stageId) => {
    return blocks.value.find(b => b.id === stageId)
  }

  return {
  blocks,
  isLoadingBlocks,
  loadBlocks,
  createNewBlock,
  updateBlock,
  updateStageDependencies,
  patchStageDepLabel,
  applyBlockFromApi,
  deleteBlock,
  updateBlockDate,
  forceUpdatePositions,
  completedReleasesCount,
  inProgressReleasesCount,
  totalTasksCount,
  completedTasksCount,
  overallProgress,
    totalEffort,
    completedEffort,
    completedEffortPercent,
  getTaskProgress,
  stageProgressPercent,
  stageTimelineStatus,
  getCompletedTasksCount,
  blockHasTaskInProgress,
  getBlockBackgroundColor,
  getEffortColor,
  getPriorityClass,
  getPriorityIcon,
  getProgressColor,
    getOriginalBlock,
  calculateBlockHeight
  }
}