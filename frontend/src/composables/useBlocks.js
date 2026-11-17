import { ref, computed } from 'vue'
import axios from 'axios'
import { useAuth } from './useAuth'
import { useProjects } from './useProjects'
import { normalizeTasksArray } from '@/utils/taskModel'

// Shared singleton state for all composable consumers.
const blocks = ref([])
const isLoadingBlocks = ref(false)
const projectStats = ref(null)

const rollupServerBlockStats = (list) => {
  const source = Array.isArray(list) ? list : []
  let completedReleasesCount = 0
  let inProgressReleasesCount = 0
  let totalTasksCount = 0
  let completedTasksCount = 0
  let totalEffort = 0
  let completedEffort = 0
  for (const block of source) {
    const total = Number(block?.taskCounts?.total) || 0
    const done = Number(block?.taskCounts?.done) || 0
    const effort = Number(block?.effort) || 0
    totalTasksCount += total
    completedTasksCount += done
    totalEffort += effort
    if (block?.stageStatus === 'done') {
      completedReleasesCount += 1
      completedEffort += effort
    } else if (total > 0) {
      inProgressReleasesCount += 1
    }
  }
  return {
    completedReleasesCount,
    inProgressReleasesCount,
    totalTasksCount,
    completedTasksCount,
    overallProgress: totalTasksCount ? Math.round((completedTasksCount / totalTasksCount) * 100) : 0,
    totalEffort,
    completedEffort,
    completedEffortPercent: totalEffort ? Math.round((completedEffort / totalEffort) * 100) : 0
  }
}

const rememberServerStats = (stats) => {
  if (!stats || typeof stats !== 'object') {
    projectStats.value = rollupServerBlockStats(blocks.value)
    return
  }
  projectStats.value = {
    completedReleasesCount: Number(stats.completedReleasesCount) || 0,
    inProgressReleasesCount: Number(stats.inProgressReleasesCount) || 0,
    totalTasksCount: Number(stats.totalTasksCount) || 0,
    completedTasksCount: Number(stats.completedTasksCount) || 0,
    overallProgress: Number(stats.overallProgress) || 0,
    totalEffort: Number(stats.totalEffort) || 0,
    completedEffort: Number(stats.completedEffort) || 0,
    completedEffortPercent: Number(stats.completedEffortPercent) || 0
  }
}

const taskSignature = (tasks) => JSON.stringify((Array.isArray(tasks) ? tasks : []).map((task) => ({
  id: String(task?.id || ''),
  title: String(task?.title || ''),
  status: String(task?.status || ''),
  order: Number(task?.order) || 0,
  effort: Number(task?.effort) || 0,
  owner: String(task?.owner || ''),
  description: String(task?.description || ''),
  startDate: String(task?.startDate || ''),
  releaseDate: String(task?.releaseDate || ''),
  linkUrl: String(task?.linkUrl || ''),
  linkNote: String(task?.linkNote || ''),
  predecessorIds: Array.isArray(task?.predecessorIds) ? task.predecessorIds : [],
  predecessorLinks: Array.isArray(task?.predecessorLinks) ? task.predecessorLinks : []
})))

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
      rememberServerStats(null)
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
      rememberServerStats(Array.isArray(payload) ? null : payload?.stats)
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
    projectStats.value = rollupServerBlockStats(blocks.value)
    
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
          projectStats.value = rollupServerBlockStats(blocks.value)
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
    projectStats.value = rollupServerBlockStats(blocks.value)
    return merged
  }

  // Поля этапа — PUT /blocks. Изменённые задачи — sync, не полная замена.
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
      const previous = blocks.value.find((item) => item.id === block.id)
      if (Array.isArray(block.tasks) && taskSignature(previous?.tasks) !== taskSignature(block.tasks)) {
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

  // Даты этапа нормализует roadmap_set_block_dates.
  const updateBlockDate = async (block, dates) => {
    try {
      if (isReadOnly.value) {
        return { success: false, error: new Error('read-only') }
      }
      const patch = typeof dates === 'string' ? { releaseDate: dates, changedField: 'releaseDate' } : (dates || {})
      const response = await axios.patch(apiPath(`/blocks/${block.id}/dates`), {
        startDate: patch.startDate ?? block.startDate ?? '',
        releaseDate: patch.releaseDate ?? block.releaseDate ?? '',
        changedField: patch.changedField || ''
      })
      const merged = applyBlockFromApi(response.data, {
        stagePredecessorIds: block.stagePredecessorIds,
        stageDependencyMeta: block.stageDependencyMeta
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

  const statValue = (key) => computed(() => Number(projectStats.value?.[key]) || 0)
  const completedReleasesCount = statValue('completedReleasesCount')
  const inProgressReleasesCount = statValue('inProgressReleasesCount')
  const totalTasksCount = statValue('totalTasksCount')
  const completedTasksCount = statValue('completedTasksCount')
  const overallProgress = statValue('overallProgress')
  const totalEffort = statValue('totalEffort')
  const completedEffort = statValue('completedEffort')
  const completedEffortPercent = statValue('completedEffortPercent')

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