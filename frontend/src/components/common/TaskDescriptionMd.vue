<template>
  <div class="md-editor">
    <div class="md-toolbar">
      <div class="md-tools">
        <Tooltip label="Жирный">
          <button type="button" class="md-btn" :disabled="preview" @click="wrap('**', '**')">B</button>
        </Tooltip>
        <Tooltip label="Курсив">
          <button type="button" class="md-btn md-btn-italic" :disabled="preview" @click="wrap('*', '*')">I</button>
        </Tooltip>
        <Tooltip label="Заголовок">
          <button type="button" class="md-btn" :disabled="preview" @click="prefixLine('## ')">H</button>
        </Tooltip>
        <Tooltip label="Список">
          <button type="button" class="md-btn" :disabled="preview" @click="prefixLine('- ')">•</button>
        </Tooltip>
        <Tooltip label="Ссылка">
          <button type="button" class="md-btn" :disabled="preview" @click="insertLink">🔗</button>
        </Tooltip>
        <Tooltip label="Блок кода">
          <button type="button" class="md-btn md-btn-code" :disabled="preview" @click="insertCode">`</button>
        </Tooltip>
      </div>
      <div class="md-modes">
        <button
          type="button"
          class="md-mode"
          :class="{ active: !preview }"
          @click="preview = false"
        >Правка</button>
        <button
          type="button"
          class="md-mode"
          :class="{ active: preview }"
          @click="preview = true"
        >Превью</button>
      </div>
    </div>

    <textarea
      v-show="!preview"
      ref="textareaRef"
      class="md-textarea"
      :value="modelValue"
      :placeholder="placeholder"
      @input="onInput"
      @paste="$emit('paste', $event)"
    ></textarea>
    <div
      v-show="preview"
      ref="previewRoot"
      class="md-preview"
      title="Двойной клик — правка"
      v-html="previewHtml"
      @dblclick="focusTextarea"
      @paste="$emit('paste', $event)"
    ></div>
  </div>
</template>

<script setup>
import { computed, nextTick, onBeforeUnmount, onMounted, ref, watch } from 'vue'
import { marked } from 'marked'
import DOMPurify from 'dompurify'
import axios from 'axios'
import { useAuth } from '@/composables/useAuth'
import hljs from 'highlight.js/lib/core'
import sql from 'highlight.js/lib/languages/sql'
import javascript from 'highlight.js/lib/languages/javascript'
import json from 'highlight.js/lib/languages/json'
import xml from 'highlight.js/lib/languages/xml'
import bash from 'highlight.js/lib/languages/bash'
import Tooltip from './Tooltip.vue'

hljs.registerLanguage('sql', sql)
hljs.registerLanguage('javascript', javascript)
hljs.registerLanguage('js', javascript)
hljs.registerLanguage('json', json)
hljs.registerLanguage('xml', xml)
hljs.registerLanguage('html', xml)
hljs.registerLanguage('bash', bash)
hljs.registerLanguage('shell', bash)

const props = defineProps({
  modelValue: { type: String, default: '' },
  blockId: { type: [String, Number], default: '' },
  taskId: { type: [String, Number], default: '' },
  placeholder: {
    type: String,
    default: 'Описание в Markdown. Картинку можно вставить из буфера или перетащить сюда.'
  }
})

const emit = defineEmits(['update:modelValue', 'paste'])

const { API_URL } = useAuth()
const textareaRef = ref(null)
const previewRoot = ref(null)
const preview = ref(true)
const attachmentUrls = new Map()

const escapeHtml = (value) =>
  String(value)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')

const highlightCode = (code, lang) => {
  const language = String(lang || '').trim().toLowerCase()
  if (language && hljs.getLanguage(language)) {
    try {
      return hljs.highlight(code, { language }).value
    } catch {
      /* fall through */
    }
  }
  try {
    return hljs.highlightAuto(code).value
  } catch {
    return escapeHtml(code)
  }
}

const safeImageUrl = (href) => {
  const url = String(href || '').trim()
  if (/^https?:\/\//i.test(url)) return url
  return ''
}

marked.use({
  gfm: true,
  breaks: true,
  renderer: {
    code({ text, lang }) {
      const language = String(lang || '').trim()
      const highlighted = highlightCode(text, language)
      const className = language
        ? `hljs language-${escapeHtml(language)}`
        : 'hljs'
      return `<pre><code class="${className}">${highlighted}</code></pre>\n`
    },
    image({ href, text }) {
      const alt = escapeHtml(text || 'изображение')
      const attachment = String(href || '').trim().match(/^attachment:([A-Za-z0-9_-]+)$/i)
      if (attachment) {
        return `<img data-file-id="${escapeHtml(attachment[1])}" alt="${alt}" class="md-image is-loading">`
      }
      const src = safeImageUrl(href)
      if (!src) return ''
      return `<img src="${escapeHtml(src)}" alt="${alt}" class="md-image" loading="lazy">`
    }
  }
})

const previewHtml = computed(() => {
  const raw = String(props.modelValue || '').trim()
  if (!raw) return '<p class="md-empty">Нет описания</p>'
  return DOMPurify.sanitize(marked.parse(raw), {
    ADD_ATTR: ['class', 'data-file-id', 'loading']
  })
})

const revokeAttachmentUrls = () => {
  const previous = [...attachmentUrls.values()]
  attachmentUrls.clear()
  for (const value of previous) {
    Promise.resolve(value).then((url) => {
      if (typeof url === 'string' && url.startsWith('blob:')) URL.revokeObjectURL(url)
    })
  }
}

const loadAttachmentUrl = (fileId) => {
  const key = `${props.blockId}:${props.taskId}:${fileId}`
  if (attachmentUrls.has(key)) return attachmentUrls.get(key)
  if (!props.blockId || !props.taskId) return Promise.resolve('')
  const pending = axios
    .get(`${API_URL}/blocks/${props.blockId}/tasks/${props.taskId}/files/${fileId}`, {
      responseType: 'blob',
      timeout: 180000
    })
    .then((response) => {
      const type = String(response.data?.type || '')
      if (!type.startsWith('image/') || type === 'image/svg+xml') return ''
      const url = URL.createObjectURL(response.data)
      if (!attachmentUrls.has(key)) {
        URL.revokeObjectURL(url)
        return ''
      }
      attachmentUrls.set(key, url)
      return url
    })
    .catch(() => {
      attachmentUrls.delete(key)
      return ''
    })
  attachmentUrls.set(key, pending)
  return pending
}

const hydrateImages = async () => {
  await nextTick()
  const root = previewRoot.value
  if (!root || !preview.value) return
  const nodes = [...root.querySelectorAll('img[data-file-id]')]
  await Promise.all(nodes.map(async (img) => {
    const fileId = img.getAttribute('data-file-id')
    if (!fileId) return
    const url = await loadAttachmentUrl(fileId)
    if (!img.isConnected) return
    if (!url) {
      img.classList.remove('is-loading')
      img.classList.add('is-broken')
      img.alt = 'Не удалось показать изображение'
      return
    }
    img.src = url
    img.classList.remove('is-loading')
  }))
}

watch(
  () => [previewHtml.value, preview.value, props.blockId, props.taskId],
  async (next, prev) => {
    if (prev && (prev[2] !== next[2] || prev[3] !== next[3])) revokeAttachmentUrls()
    await hydrateImages()
  }
)
onMounted(hydrateImages)
onBeforeUnmount(revokeAttachmentUrls)

const onInput = (event) => {
  emit('update:modelValue', event.target.value)
}

const focusTextarea = async () => {
  preview.value = false
  await nextTick()
  textareaRef.value?.focus()
}

const applyValue = async (next, selectionStart, selectionEnd) => {
  emit('update:modelValue', next)
  await nextTick()
  const el = textareaRef.value
  if (!el) return
  el.focus()
  el.setSelectionRange(selectionStart, selectionEnd)
}

const wrap = async (before, after) => {
  await focusTextarea()
  const el = textareaRef.value
  if (!el) return
  const value = String(props.modelValue || '')
  const start = el.selectionStart ?? 0
  const end = el.selectionEnd ?? 0
  const selected = value.slice(start, end) || 'текст'
  const next = value.slice(0, start) + before + selected + after + value.slice(end)
  const cursorStart = start + before.length
  const cursorEnd = cursorStart + selected.length
  await applyValue(next, cursorStart, cursorEnd)
}

/** Инлайн `код` для одной строки; для нескольких — fenced-блок ```...``` */
const insertCode = async () => {
  await focusTextarea()
  const el = textareaRef.value
  if (!el) return
  const value = String(props.modelValue || '')
  const start = el.selectionStart ?? 0
  const end = el.selectionEnd ?? 0
  const selected = value.slice(start, end)
  const isBlock = !selected || selected.includes('\n')
  if (!isBlock) {
    await wrap('`', '`')
    return
  }
  const body = selected || 'код'
  const fence = '```'
  const snippet = `${fence}\n${body}\n${fence}`
  const next = value.slice(0, start) + snippet + value.slice(end)
  const cursorStart = start + fence.length + 1
  await applyValue(next, cursorStart, cursorStart + body.length)
}

const prefixLine = async (prefix) => {
  await focusTextarea()
  const el = textareaRef.value
  if (!el) return
  const value = String(props.modelValue || '')
  const start = el.selectionStart ?? 0
  const end = el.selectionEnd ?? 0
  const lineStart = value.lastIndexOf('\n', Math.max(0, start - 1)) + 1
  const selected = value.slice(start, end)
  if (!selected.includes('\n')) {
    const next = value.slice(0, lineStart) + prefix + value.slice(lineStart)
    const shift = prefix.length
    await applyValue(next, start + shift, end + shift)
    return
  }
  const block = value.slice(lineStart, end)
  const replaced = block
    .split('\n')
    .map((line) => (line.startsWith(prefix) ? line : `${prefix}${line}`))
    .join('\n')
  const next = value.slice(0, lineStart) + replaced + value.slice(end)
  await applyValue(next, lineStart, lineStart + replaced.length)
}

const insertMarkdown = async (snippet, { showPreview = false } = {}) => {
  const piece = String(snippet || '').replace(/^\n+/, '').replace(/\n+$/, '')
  if (!piece) return
  const value = String(props.modelValue || '')
  if (preview.value) {
    const base = value.replace(/\s+$/, '')
    emit('update:modelValue', `${base}${base ? '\n\n' : ''}${piece}\n`)
  } else {
    const el = textareaRef.value
    const start = el?.selectionStart ?? value.length
    const end = el?.selectionEnd ?? value.length
    const next = value.slice(0, start) + piece + value.slice(end)
    const cursor = start + piece.length
    await applyValue(next, cursor, cursor)
  }
  if (showPreview) preview.value = true
}

const insertLink = async () => {
  await focusTextarea()
  const el = textareaRef.value
  if (!el) return
  const value = String(props.modelValue || '')
  const start = el.selectionStart ?? 0
  const end = el.selectionEnd ?? 0
  const selected = value.slice(start, end) || 'текст'
  const snippet = `[${selected}](https://)`
  const next = value.slice(0, start) + snippet + value.slice(end)
  const urlStart = start + selected.length + 3
  await applyValue(next, urlStart, urlStart + 'https://'.length)
}

defineExpose({ insertMarkdown })
</script>

<style scoped>
.md-editor {
  display: flex;
  flex-direction: column;
  flex: 1;
  min-height: 220px;
  border: 1px solid #cbd5e1;
  border-radius: 8px;
  overflow: hidden;
  background: #fff;
}
.md-toolbar {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 8px;
  padding: 6px 8px;
  border-bottom: 1px solid #e2e8f0;
  background: #f8fafc;
}
.md-tools,
.md-modes {
  display: inline-flex;
  align-items: center;
  gap: 4px;
}
.md-btn,
.md-mode {
  min-width: 28px;
  height: 28px;
  padding: 0 8px;
  border: 1px solid transparent;
  border-radius: 6px;
  background: transparent;
  color: #334155;
  font-size: 0.82rem;
  font-weight: 700;
  cursor: pointer;
  font-family: inherit;
}
.md-btn:hover:not(:disabled),
.md-mode:hover {
  background: #e2e8f0;
}
.md-btn:disabled {
  opacity: 0.4;
  cursor: default;
}
.md-btn-italic {
  font-style: italic;
}
.md-btn-code {
  font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace;
  font-weight: 600;
}
.md-mode.active {
  background: #dbeafe;
  border-color: #bfdbfe;
  color: #1d4ed8;
}
.md-textarea,
.md-preview {
  flex: 1;
  min-height: 220px;
  width: 100%;
  box-sizing: border-box;
  padding: 10px 12px;
  margin: 0;
  border: none;
  outline: none;
  font-size: 0.95rem;
  line-height: 1.5;
  font-family: inherit;
  color: #0f172a;
  background: #fff;
  overflow: auto;
}
.md-textarea {
  resize: none;
}
.md-preview {
  white-space: normal;
  cursor: text;
}
.md-preview :deep(p) {
  margin: 0 0 0.7em;
}
.md-preview :deep(h1),
.md-preview :deep(h2),
.md-preview :deep(h3) {
  margin: 0.4em 0 0.5em;
  line-height: 1.25;
  color: #0f172a;
}
.md-preview :deep(h1) { font-size: 1.35rem; }
.md-preview :deep(h2) { font-size: 1.15rem; }
.md-preview :deep(h3) { font-size: 1.05rem; }
.md-preview :deep(ul),
.md-preview :deep(ol) {
  margin: 0 0 0.7em;
  padding-left: 1.3em;
}
.md-preview :deep(a) {
  color: #1d4ed8;
}
.md-preview :deep(code) {
  padding: 0.1em 0.35em;
  border-radius: 4px;
  background: #f3f3f3;
  font-family: Consolas, 'Courier New', ui-monospace, Menlo, monospace;
  font-size: 0.9em;
  color: #24292f;
}
.md-preview :deep(pre) {
  margin: 0 0 0.7em;
  padding: 12px 14px;
  border-radius: 6px;
  background: #f8f8f8;
  border: 1px solid #ececec;
  color: #24292f;
  overflow: auto;
}
.md-preview :deep(pre code) {
  display: block;
  padding: 0;
  background: transparent;
  color: inherit;
  font-size: 0.88rem;
  line-height: 1.45;
  white-space: pre;
}
/* Светлая подсветка в духе VS Code Light+ */
.md-preview :deep(pre .hljs-keyword),
.md-preview :deep(pre .hljs-selector-tag),
.md-preview :deep(pre .hljs-literal),
.md-preview :deep(pre .hljs-name),
.md-preview :deep(pre .hljs-built_in) {
  color: #a31515;
}
.md-preview :deep(pre .hljs-string),
.md-preview :deep(pre .hljs-title),
.md-preview :deep(pre .hljs-section),
.md-preview :deep(pre .hljs-attribute),
.md-preview :deep(pre .hljs-symbol),
.md-preview :deep(pre .hljs-bullet),
.md-preview :deep(pre .hljs-addition) {
  color: #0451a5;
}
.md-preview :deep(pre .hljs-comment),
.md-preview :deep(pre .hljs-quote),
.md-preview :deep(pre .hljs-deletion),
.md-preview :deep(pre .hljs-meta) {
  color: #008000;
}
.md-preview :deep(pre .hljs-number),
.md-preview :deep(pre .hljs-regexp),
.md-preview :deep(pre .hljs-variable),
.md-preview :deep(pre .hljs-template-variable),
.md-preview :deep(pre .hljs-link),
.md-preview :deep(pre .hljs-selector-attr),
.md-preview :deep(pre .hljs-selector-pseudo) {
  color: #098658;
}
.md-preview :deep(pre .hljs-type),
.md-preview :deep(pre .hljs-params) {
  color: #267f99;
}
.md-preview :deep(.md-empty) {
  margin: 0;
  color: #94a3b8;
}
.md-preview :deep(img.md-image) {
  display: block;
  max-width: 100%;
  height: auto;
  margin: 0.4em 0 0.8em;
  border: 1px solid #e2e8f0;
  border-radius: 8px;
  background: #f8fafc;
}
.md-preview :deep(img.md-image.is-loading),
.md-preview :deep(img.md-image.is-broken) {
  min-height: 72px;
  padding: 12px;
  color: #64748b;
  font-size: 0.85rem;
}
</style>
