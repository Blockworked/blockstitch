<script setup lang="ts">
import { computed } from 'vue';
import type { FloatingValueLike } from '../canvas/host';
import { getHost } from '../canvas/host';
import ValueBlock from './ValueBlock.vue';

const props = defineProps<{ floatingValue: FloatingValueLike }>();

const customColor = computed(() => getHost().floatingValueColor?.(props.floatingValue));
const isCustomReporter = computed(() => props.floatingValue.value.kind === 'Call');
</script>

<template>
  <div
    class="value-floating-card"
    :class="{
      'blockwork-custom-floating-value': !!customColor,
      'blockwork-custom-floating-operator': !!customColor && isCustomReporter,
    }"
    :style="customColor ? { '--blockwork-custom-block-color': customColor } : undefined"
    :data-floating-id="floatingValue.id"
  >
    <ValueBlock :location="{ kind: 'Floating', floating_id: floatingValue.id, path: [] }" :value="floatingValue.value" />
  </div>
</template>
