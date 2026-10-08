<template>
  <div class="app-select" :class="{ 'is-open': open, 'is-disabled': disabled }">
    <button
      ref="triggerRef"
      type="button"
      class="app-select-trigger"
      :disabled="disabled"
      @click="toggle"
    >
      <span class="app-select-value">{{ selectedLabel }}</span>
      <svg class="app-select-caret" viewBox="0 0 20 20" width="16" height="16" aria-hidden="true">
        <path d="M5 7.5 10 12.5 15 7.5" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round" />
      </svg>
    </button>
    <Teleport to="body">
      <div
        v-if="open"
        ref="menuRef"
        class="app-select-menu"
        :style="menuStyle"
        role="listbox"
      >
        <button
          v-for="option in options"
          :key="String(option.value)"
          type="button"
          class="app-select-option"
          :class="{ 'is-selected': option.value === modelValue }"
          role="option"
          :aria-selected="option.value === modelValue"
          @click="choose(option)"
        >
          {{ option.label }}
        </button>
        <div v-if="!options.length" class="app-select-empty">{{ placeholder || 'Нет вариантов' }}</div>
      </div>
    </Teleport>
  </div>
</template>

<script setup>
import { computed, nextTick, onBeforeUnmount, onMounted, ref } from 'vue'

const props = defineProps({
  modelValue: { type: [String, Number], default: '' },
  options: { type: Array, default: () => [] },
  disabled: { type: Boolean, default: false },
  placeholder: { type: String, default: '' }
})

const emit = defineEmits(['update:modelValue'])

const triggerRef = ref(null)
const menuRef = ref(null)
const open = ref(false)
const menuStyle = ref({})

const selectedLabel = computed(() => {
  const found = props.options.find((item) => item.value === props.modelValue)
  return found?.label || props.placeholder || ''
})

const placeMenu = () => {
  const trigger = triggerRef.value
  const menu = menuRef.value
  if (!trigger) return
  const rect = trigger.getBoundingClientRect()
  const menuHeight = menu?.getBoundingClientRect().height || Math.min(240, props.options.length * 36 + 8)
  const gap = 4
  let top = rect.bottom + gap
  if (top + menuHeight > window.innerHeight - 8) {
    top = Math.max(8, rect.top - menuHeight - gap)
  }
  menuStyle.value = {
    top: `${Math.round(top)}px`,
    left: `${Math.round(rect.left)}px`,
    width: `${Math.round(rect.width)}px`
  }
}

const close = () => {
  open.value = false
}

const toggle = async () => {
  if (props.disabled) return
  open.value = !open.value
  if (!open.value) return
  await nextTick()
  placeMenu()
}

const choose = (option) => {
  emit('update:modelValue', option.value)
  close()
}

const onDocumentPointerDown = (event) => {
  if (!open.value) return
  const target = event.target
  if (triggerRef.value?.contains(target) || menuRef.value?.contains(target)) return
  close()
}

const onKeydown = (event) => {
  if (event.key === 'Escape') close()
}

onMounted(() => {
  document.addEventListener('pointerdown', onDocumentPointerDown, true)
  window.addEventListener('resize', close)
  window.addEventListener('scroll', close, true)
  document.addEventListener('keydown', onKeydown)
})

onBeforeUnmount(() => {
  document.removeEventListener('pointerdown', onDocumentPointerDown, true)
  window.removeEventListener('resize', close)
  window.removeEventListener('scroll', close, true)
  document.removeEventListener('keydown', onKeydown)
})
</script>

<style scoped>
.app-select {
  width: 100%;
  font-family: 'Inter', -apple-system, BlinkMacSystemFont, sans-serif;
}
.app-select-trigger {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 8px;
  width: 100%;
  box-sizing: border-box;
  min-height: 38px;
  padding: 8px 12px;
  border: 1px solid #e2e8f0;
  border-radius: 8px;
  background: #fff;
  color: #0f172a;
  font-size: 0.9rem;
  font-weight: 400;
  font-family: 'Inter', -apple-system, BlinkMacSystemFont, sans-serif;
  line-height: 1.5;
  text-align: left;
  cursor: pointer;
}
.app-select-trigger:hover:not(:disabled) {
  border-color: #cbd5e1;
}
.app-select.is-open .app-select-trigger {
  border-color: #3b82f6;
  box-shadow: 0 0 0 3px rgba(59, 130, 246, 0.1);
}
.app-select-trigger:disabled {
  cursor: default;
  color: #64748b;
  background: #f8fafc;
}
.app-select-value {
  min-width: 0;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}
.app-select-caret {
  flex-shrink: 0;
  color: #64748b;
}
.app-select.is-open .app-select-caret {
  transform: rotate(180deg);
}
.app-select-menu {
  position: fixed;
  z-index: 13000;
  box-sizing: border-box;
  max-height: 240px;
  overflow: auto;
  padding: 6px;
  border: 1px solid #e2e8f0;
  border-radius: 8px;
  background: #fff;
  font-family: 'Inter', -apple-system, BlinkMacSystemFont, sans-serif;
  font-size: 0.9rem;
  font-weight: 400;
  line-height: 1.5;
  box-shadow:
    0 10px 24px rgba(15, 23, 42, 0.12),
    0 2px 6px rgba(15, 23, 42, 0.06);
}
.app-select-option {
  display: block;
  width: 100%;
  box-sizing: border-box;
  padding: 8px 10px;
  border: none;
  border-radius: 6px;
  background: transparent;
  color: #0f172a;
  font-size: 0.9rem;
  font-weight: 400;
  font-family: 'Inter', -apple-system, BlinkMacSystemFont, sans-serif;
  line-height: 1.5;
  text-align: left;
  cursor: pointer;
}
.app-select-option:hover {
  background: #f8fafc;
}
.app-select-option.is-selected {
  background: #eff6ff;
  color: #1d4ed8;
}
.app-select-empty {
  padding: 8px 10px;
  color: #64748b;
  font-size: 0.85rem;
}
</style>
