<script setup lang="ts">
// A palette instruction's numeric field (e.g. a wait duration, a move-mouse
// x/y) — same bare-leaf appearance as a real ValueBlock leaf, but
// deliberately not a drag source/drop target: sidebar prefabs never carry
// operators or variables in a plain numeric field, only literal numbers, and
// the whole sidebar already refuses value drops (see canvas/canvasDrag.ts's
// isOverSidebar), so this component simply never wires up that machinery.
import { computed } from 'vue';
import AutosizeInput from '../ui/AutosizeInput.vue';
import { numberValue, type ValueNode } from '../values/valueNode';

const props = defineProps<{ modelValue: ValueNode; placeholder?: string }>();
// Narrow emit type (just the 'Number' case, not the whole ValueNode union)
// so a host with its own narrower `Op.op` type can still assign the result
// directly — see values/valueNode.ts's numberValue for the same reasoning.
const emit = defineEmits<{ 'update:modelValue': [Extract<ValueNode, { kind: 'Number' }>] }>();

const text = computed(() => String(props.modelValue.kind === 'Number' ? props.modelValue.value : 0));

function onInput(v: string) {
  const n = Number(v);
  if (v.trim() !== '' && !isNaN(n)) emit('update:modelValue', numberValue(n));
}
</script>

<template>
  <span class="value-block">
    <AutosizeInput :model-value="text" :min-chars="2" :placeholder="placeholder" @update:model-value="onInput" />
  </span>
</template>
