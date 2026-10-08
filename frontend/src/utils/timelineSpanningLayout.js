/** Раскладка карточек таймлайна: span по датам + вертикальная паковка, как на карте Шивы. */

export const TIMELINE_COLUMN_PAD_X_PX = 12
export const TIMELINE_LANE_GAP_PX = 12
export const TIMELINE_BODY_PAD_TOP_PX = 20
export const TIMELINE_DEFAULT_CARD_HEIGHT_PX = 80

export function parseBlockDate(value) {
  if (!value) return null
  const date = value instanceof Date ? value : new Date(value)
  if (Number.isNaN(date.getTime())) return null
  return date
}

/** Плановый отрезок этапа: startDate → releaseDate; если одной даты нет — одна точка. */
export function getBlockPlanRange(block) {
  const start = parseBlockDate(block?.startDate)
  const end = parseBlockDate(block?.releaseDate)
  if (!start && !end) return { start: null, end: null }
  if (!start) return { start: end, end }
  if (!end) return { start, end: start }
  if (start.getTime() <= end.getTime()) return { start, end }
  return { start: end, end: start }
}

export function getBlockPlacementIndex(block, getIndexFromDate) {
  const { start, end } = getBlockPlanRange(block)
  const source = start || end
  if (!source) return null
  const index = getIndexFromDate(source)
  return Number.isFinite(index) ? index : null
}

export function getBlockColumnSpan(block, getIndexFromDate) {
  const { start, end } = getBlockPlanRange(block)
  if (!start || !end) return 1
  const startIndex = getIndexFromDate(start)
  const endIndex = getIndexFromDate(end)
  if (!Number.isFinite(startIndex) || !Number.isFinite(endIndex)) return 1
  return Math.max(1, endIndex - startIndex + 1)
}

/** Все индексы колонок, которые занимает этап (для границ шкалы). */
export function getBlockCoveredIndexes(block, getIndexFromDate) {
  const placementIndex = getBlockPlacementIndex(block, getIndexFromDate)
  if (placementIndex == null) return []
  const span = getBlockColumnSpan(block, getIndexFromDate)
  const result = []
  for (let i = 0; i < span; i += 1) {
    result.push(placementIndex + i)
  }
  return result
}

export function clipPlacementToColumns(startIndex, columnSpan, columns) {
  if (!columns.length) return null
  if (startIndex == null || !Number.isFinite(startIndex)) return null
  const first = columns[0].index
  const last = columns[columns.length - 1].index
  const span = Math.max(1, Number(columnSpan) || 1)
  const endIndex = startIndex + span - 1
  if (endIndex < first || startIndex > last) return null
  const clippedStart = Math.max(startIndex, first)
  const clippedEnd = Math.min(endIndex, last)
  return {
    startIndex: clippedStart,
    columnSpan: Math.max(1, clippedEnd - clippedStart + 1),
    placementKey: String(clippedStart)
  }
}

function isWideSpan(columnSpan) {
  return columnSpan >= 2
}

function endTimeMs(block) {
  const { end } = getBlockPlanRange(block)
  return end ? end.getTime() : Number.POSITIVE_INFINITY
}

function compareBlockId(a, b) {
  return String(a.id).localeCompare(String(b.id), undefined, { numeric: true })
}

/** В колонке: сначала широкие по дате окончания, затем остальные. */
export function sortStagesInTimelineColumn(stages, getColumnSpan) {
  const spanById = new Map()
  for (const stage of stages) {
    spanById.set(String(stage.id), getColumnSpan(stage))
  }

  return [...stages].sort((a, b) => {
    const spanA = spanById.get(String(a.id)) ?? 1
    const spanB = spanById.get(String(b.id)) ?? 1
    const wideA = isWideSpan(spanA)
    const wideB = isWideSpan(spanB)
    if (wideA !== wideB) return wideA ? -1 : 1
    const byEnd = endTimeMs(a) - endTimeMs(b)
    if (byEnd !== 0) return byEnd
    return compareBlockId(a, b)
  })
}

export function buildClippedPlacements(blocks, columns, getIndexFromDate) {
  const placements = new Map()
  for (const block of blocks) {
    const rawStart = getBlockPlacementIndex(block, getIndexFromDate)
    const rawSpan = getBlockColumnSpan(block, getIndexFromDate)
    const clipped = clipPlacementToColumns(rawStart, rawSpan, columns)
    if (clipped) placements.set(String(block.id), clipped)
  }
  return placements
}

export function buildTimelineLayoutColumns(columns, blocks, placements) {
  const getColumnSpan = (block) => placements.get(String(block.id))?.columnSpan ?? 1
  return columns.map((column) => {
    const key = String(column.index)
    const stages = sortStagesInTimelineColumn(
      blocks.filter((block) => placements.get(String(block.id))?.placementKey === key),
      getColumnSpan
    )
    return {
      ...column,
      key,
      startX: Number(column.startX ?? column.visibleStartX ?? 0),
      endX: Number(column.endX ?? column.visibleEndX ?? 0),
      stages
    }
  })
}

function doColumnRangesOverlap(aStart, aSpan, bStart, bSpan) {
  return aStart < bStart + bSpan && bStart < aStart + aSpan
}

function doVerticalRangesOverlap(aTop, aBottom, bTop, bBottom) {
  return aTop < bBottom && bTop < aBottom
}

function collectStagesInLayoutOrder(columns) {
  const result = []
  for (const column of columns) {
    for (const stage of column.stages) result.push(stage)
  }
  return result
}

function buildColumnIndexByKey(columns) {
  return new Map(columns.map((column, index) => [column.key, index]))
}

function resolveStageStartCol(stage, columnIndexByKey, getPlacementKey) {
  const placementKey = getPlacementKey(stage)
  if (placementKey == null) return 0
  return columnIndexByKey.get(String(placementKey)) ?? 0
}

function resolveStageColumnSpan(stage, getColumnSpan) {
  const colSpan = getColumnSpan(stage)
  return colSpan > 0 ? colSpan : 1
}

function resolveStageHeight(heights, stageId, fallbackHeight) {
  const height = heights[stageId]
  if (height == null || height <= 0) {
    return fallbackHeight > 0 ? fallbackHeight : TIMELINE_DEFAULT_CARD_HEIGHT_PX
  }
  return height
}

function buildTimelineCardGeometry(startCol, colSpan, columns, columnPadXPx) {
  const first = columns[startCol]
  const last = columns[Math.min(startCol + colSpan - 1, columns.length - 1)]
  if (!first || !last) {
    return { left: columnPadXPx, width: 0 }
  }
  return {
    left: first.startX + columnPadXPx,
    width: Math.max(0, last.endX - first.startX - columnPadXPx * 2)
  }
}

function filterColumnOverlappingPlaced(placed, startCol, colSpan) {
  const result = []
  for (const previous of placed) {
    if (doColumnRangesOverlap(startCol, colSpan, previous.startCol, previous.colSpan)) {
      result.push(previous)
    }
  }
  return result
}

function findPlacementTop(height, columnOverlappingPlaced, baseTop, laneGapPx) {
  if (height <= 0) return baseTop
  let top = baseTop
  let guard = 0
  while (guard++ <= columnOverlappingPlaced.length) {
    const bottom = top + height
    let nextTop = null
    for (const previous of columnOverlappingPlaced) {
      if (!doVerticalRangesOverlap(top, bottom, previous.top, previous.top + previous.height)) {
        continue
      }
      const candidate = previous.top + previous.height + laneGapPx
      if (nextTop == null || candidate > nextTop) nextTop = candidate
    }
    if (nextTop == null) return top
    top = nextTop
  }
  return top
}

function computeTimelineCardPositions(params) {
  const {
    columns,
    heights,
    estimateHeights,
    bodyPaddingTopPx,
    laneGapPx,
    columnPadXPx,
    getColumnSpan,
    getPlacementKey
  } = params

  const columnIndexByKey = buildColumnIndexByKey(columns)
  const baseTop = bodyPaddingTopPx
  const layoutOrder = collectStagesInLayoutOrder(columns)
  const placed = []
  const positions = {}

  for (const stage of layoutOrder) {
    const stageId = String(stage.id)
    const startCol = resolveStageStartCol(stage, columnIndexByKey, getPlacementKey)
    const colSpan = resolveStageColumnSpan(stage, getColumnSpan)
    const height = resolveStageHeight(
      heights,
      stageId,
      Number(estimateHeights?.[stageId] || 0)
    )
    const columnOverlappingPlaced = filterColumnOverlappingPlaced(placed, startCol, colSpan)
    const top = findPlacementTop(height, columnOverlappingPlaced, baseTop, laneGapPx)
    const geometry = buildTimelineCardGeometry(startCol, colSpan, columns, columnPadXPx)

    positions[stageId] = { top, ...geometry }
    placed.push({
      stageId,
      startCol,
      colSpan,
      top,
      height
    })
  }

  return positions
}

function computeColumnBodyMinHeightsPx(params) {
  const {
    columns,
    heights,
    estimateHeights,
    bodyPaddingTopPx,
    laneGapPx,
    getColumnSpan,
    getPlacementKey,
    positions
  } = params

  const columnIndexByKey = buildColumnIndexByKey(columns)
  const minHeights = columns.map(() => bodyPaddingTopPx)

  for (const column of columns) {
    for (const stage of column.stages) {
      const stageId = String(stage.id)
      const columnIndex = resolveStageStartCol(stage, columnIndexByKey, getPlacementKey)
      const position = positions[stageId]
      const height = resolveStageHeight(
        heights,
        stageId,
        Number(estimateHeights?.[stageId] || 0)
      )
      if (!position) continue
      const colSpan = resolveStageColumnSpan(stage, getColumnSpan)
      const bottomInBody = position.top + height + laneGapPx
      for (let col = columnIndex; col < columnIndex + colSpan && col < minHeights.length; col += 1) {
        minHeights[col] = Math.max(minHeights[col], bottomInBody)
      }
    }
  }

  return minHeights
}

export function computeTimelineLayout(params) {
  const positions = computeTimelineCardPositions(params)
  return {
    positions,
    columnBodyMinHeightsPx: computeColumnBodyMinHeightsPx({
      ...params,
      positions
    })
  }
}

export function layoutTimelineBlocks({
  columns,
  blocks,
  heights,
  estimateHeight,
  getIndexFromDate,
  bodyPaddingTopPx = TIMELINE_BODY_PAD_TOP_PX,
  laneGapPx = TIMELINE_LANE_GAP_PX,
  columnPadXPx = TIMELINE_COLUMN_PAD_X_PX
}) {
  const datedBlocks = (blocks || []).filter((block) => getBlockPlanRange(block).start)
  const placements = buildClippedPlacements(datedBlocks, columns, getIndexFromDate)
  const layoutColumns = buildTimelineLayoutColumns(columns, datedBlocks, placements)
  const getColumnSpan = (block) => placements.get(String(block.id))?.columnSpan ?? 1
  const getPlacementKey = (block) => placements.get(String(block.id))?.placementKey ?? null
  const estimateHeights = {}
  const measuredHeights = {}
  for (const block of datedBlocks) {
    const id = String(block.id)
    const measured = Number(heights?.[id] || 0)
    if (measured > 0) measuredHeights[id] = measured
    if (typeof estimateHeight === 'function') {
      estimateHeights[id] = estimateHeight(block)
    }
  }

  const layout = computeTimelineLayout({
    columns: layoutColumns,
    heights: measuredHeights,
    estimateHeights,
    bodyPaddingTopPx,
    laneGapPx,
    columnPadXPx,
    getColumnSpan,
    getPlacementKey
  })

  return {
    ...layout,
    placements
  }
}
