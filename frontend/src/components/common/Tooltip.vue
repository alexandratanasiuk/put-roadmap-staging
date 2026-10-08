<template>
  <span
    ref="triggerRef"
    class="app-tooltip-trigger"
    :class="{ 'is-fill': fill }"
    @mouseenter="onEnter"
    @mousemove="onMove"
    @mouseleave="onLeave"
    @focusin="onEnter"
    @focusout="onLeave"
    @dragstart="onLeaveImmediate"
  >
    <slot />
  </span>
</template>

<script setup>
import { onBeforeUnmount, ref } from 'vue'
import {
  hideAppTooltip,
  moveAppTooltip,
  scheduleAppTooltip,
  scheduleHideAppTooltip
} from './tooltipLayer'

const props = defineProps({
  label: { type: String, default: '' },
  position: { type: String, default: 'top' },
  delay: { type: Number, default: 180 },
  hideArrow: { type: Boolean, default: false },
  fill: { type: Boolean, default: false }
})

const triggerRef = ref(null)

const options = () => ({
  label: props.label,
  position: props.position,
  delay: props.delay,
  hideArrow: props.hideArrow
})

const onEnter = (event) => {
  scheduleAppTooltip(triggerRef.value, options(), event)
}

const onMove = (event) => {
  moveAppTooltip(triggerRef.value, event)
}

const onLeave = () => {
  scheduleHideAppTooltip(triggerRef.value)
}

const onLeaveImmediate = () => {
  hideAppTooltip(triggerRef.value)
}

onBeforeUnmount(() => {
  hideAppTooltip(triggerRef.value)
})
</script>

<style scoped>
.app-tooltip-trigger {
  display: inline-flex;
  align-items: center;
  max-width: 100%;
  min-width: 0;
  vertical-align: middle;
}
.app-tooltip-trigger.is-fill {
  display: block;
  flex: 1 1 auto;
  width: auto;
  min-width: 0;
}
</style>
