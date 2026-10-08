const STYLE_ID = 'app-tooltip-layer-style'
const layer = {
  el: null,
  text: null,
  arrow: null,
  owner: null,
  showTimer: null,
  hideTimer: null,
  viewportBound: false,
  x: 0,
  y: 0,
  position: 'top',
  hideArrow: false
}

const css = `
.app-tooltip {
  position: fixed;
  z-index: 12050;
  display: none;
  max-width: 280px;
  padding: 6px 12px;
  border: 1px solid #e2e8f0;
  border-radius: 6px;
  background: #fff;
  color: #475569;
  font-family: Inter, system-ui, -apple-system, 'Segoe UI', Roboto, Arial, sans-serif;
  font-size: 12px;
  font-weight: 500;
  line-height: 1.35;
  white-space: pre-wrap;
  overflow-wrap: anywhere;
  word-break: break-word;
  box-shadow:
    0 10px 24px rgba(15, 23, 42, 0.12),
    0 2px 6px rgba(15, 23, 42, 0.06);
  pointer-events: none;
}
.app-tooltip.is-open {
  display: block;
  animation: app-tooltip-in 0.12s ease-out;
}
.app-tooltip-arrow {
  position: absolute;
  left: var(--arrow-x, 50%);
  width: 8px;
  height: 8px;
  background: #fff;
  border: 1px solid #e2e8f0;
  transform: translateX(-50%) rotate(45deg);
}
.app-tooltip.is-top .app-tooltip-arrow {
  bottom: -5px;
  border-top: none;
  border-left: none;
}
.app-tooltip.is-bottom .app-tooltip-arrow {
  top: -5px;
  border-bottom: none;
  border-right: none;
}
.app-tooltip.no-arrow .app-tooltip-arrow {
  display: none;
}
@keyframes app-tooltip-in {
  from { opacity: 0; transform: translateY(2px); }
  to { opacity: 1; transform: translateY(0); }
}
`

const clearTimers = () => {
  if (layer.showTimer) {
    clearTimeout(layer.showTimer)
    layer.showTimer = null
  }
  if (layer.hideTimer) {
    clearTimeout(layer.hideTimer)
    layer.hideTimer = null
  }
}

const onViewportChange = () => {
  hideAppTooltip()
}

const ensureLayer = () => {
  if (typeof document === 'undefined') return null
  if (!layer.viewportBound) {
    window.addEventListener('scroll', onViewportChange, true)
    window.addEventListener('resize', onViewportChange)
    layer.viewportBound = true
  }
  if (!document.getElementById(STYLE_ID)) {
    const style = document.createElement('style')
    style.id = STYLE_ID
    style.textContent = css
    document.head.appendChild(style)
  }
  if (layer.el) return layer.el
  const el = document.createElement('div')
  el.className = 'app-tooltip'
  el.setAttribute('role', 'tooltip')
  const text = document.createElement('span')
  const arrow = document.createElement('span')
  arrow.className = 'app-tooltip-arrow'
  arrow.setAttribute('aria-hidden', 'true')
  el.appendChild(text)
  el.appendChild(arrow)
  document.body.appendChild(el)
  layer.el = el
  layer.text = text
  layer.arrow = arrow
  return el
}

const setPointer = (event, anchor) => {
  if (event && Number.isFinite(event.clientX) && Number.isFinite(event.clientY)) {
    layer.x = event.clientX
    layer.y = event.clientY
    return
  }
  if (!anchor || !anchor.getBoundingClientRect) return
  const rect = anchor.getBoundingClientRect()
  layer.x = rect.left + rect.width / 2
  layer.y = rect.top + rect.height / 2
}

const place = () => {
  const el = layer.el
  if (!el) return
  const size = el.getBoundingClientRect()
  const gap = 12
  const x = layer.x
  const y = layer.y
  const preferBottom = layer.position === 'bottom'
  let pos = preferBottom ? 'bottom' : 'top'
  let top = preferBottom ? y + gap : y - size.height - gap
  if (!preferBottom && top < 8) {
    pos = 'bottom'
    top = y + gap
  } else if (preferBottom && top + size.height > window.innerHeight - 8) {
    pos = 'top'
    top = y - size.height - gap
  }
  let left = x - size.width / 2
  left = Math.min(Math.max(8, left), window.innerWidth - size.width - 8)
  const arrowX = Math.min(Math.max(12, x - left), Math.max(12, size.width - 12))
  el.classList.toggle('is-top', pos === 'top')
  el.classList.toggle('is-bottom', pos === 'bottom')
  el.style.top = `${Math.round(top)}px`
  el.style.left = `${Math.round(left)}px`
  el.style.setProperty('--arrow-x', `${Math.round(arrowX)}px`)
}

export const hideAppTooltip = (anchor) => {
  if (anchor && layer.owner && layer.owner !== anchor) return
  clearTimers()
  layer.owner = null
  if (!layer.el) return
  layer.el.classList.remove('is-open')
}

export const showAppTooltip = (anchor, options = {}, event) => {
  const label = String(options.label || '').trim()
  if (!anchor || !anchor.isConnected || !label) return
  clearTimers()
  const el = ensureLayer()
  if (!el) return
  layer.owner = anchor
  layer.position = options.position === 'bottom' ? 'bottom' : 'top'
  layer.hideArrow = Boolean(options.hideArrow)
  if (event) setPointer(event, anchor)
  else if (!layer.x && !layer.y) setPointer(null, anchor)
  layer.text.textContent = label
  el.classList.toggle('no-arrow', layer.hideArrow)
  el.classList.add('is-open')
  place()
}

export const moveAppTooltip = (anchor, event) => {
  if (!anchor || !event) return
  if (layer.owner && layer.owner !== anchor && !layer.showTimer) return
  setPointer(event, anchor)
  if (layer.el?.classList.contains('is-open')) place()
}

export const scheduleAppTooltip = (anchor, options = {}, event) => {
  if (!anchor) return
  setPointer(event, anchor)
  clearTimers()
  const delay = Number.isFinite(options.delay) ? Math.max(0, options.delay) : 180
  layer.showTimer = setTimeout(() => showAppTooltip(anchor, options), delay)
}

export const scheduleHideAppTooltip = (anchor) => {
  if (anchor && layer.owner && layer.owner !== anchor && !layer.showTimer) return
  if (layer.showTimer) {
    clearTimers()
    return
  }
  clearTimers()
  layer.hideTimer = setTimeout(() => hideAppTooltip(anchor), 80)
}

export const bindAppTooltip = (el, getOptions) => {
  const onEnter = (event) => scheduleAppTooltip(el, getOptions(), event)
  const onMove = (event) => moveAppTooltip(el, event)
  const onLeave = () => scheduleHideAppTooltip(el)
  const onDrag = () => hideAppTooltip(el)
  el.addEventListener('mouseenter', onEnter)
  el.addEventListener('mousemove', onMove)
  el.addEventListener('mouseleave', onLeave)
  el.addEventListener('focusin', onEnter)
  el.addEventListener('focusout', onLeave)
  el.addEventListener('dragstart', onDrag)
  return () => {
    el.removeEventListener('mouseenter', onEnter)
    el.removeEventListener('mousemove', onMove)
    el.removeEventListener('mouseleave', onLeave)
    el.removeEventListener('focusin', onEnter)
    el.removeEventListener('focusout', onLeave)
    el.removeEventListener('dragstart', onDrag)
    hideAppTooltip(el)
  }
}
