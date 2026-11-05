<script setup lang="ts">
// A sidebar "prefab" for one instruction type — visually a real
// .instruction-row/.instruction-shape, bound to the host's own live prefab
// state for this type (passed in as `instruction`) so it renders exactly
// what would spawn onto the canvas right now. Its fields are genuinely
// editable (the host's palette field component owns that), but editing never
// touches the backend — there's no real strand/index behind a palette entry
// — and dragging always starts from this block itself (no separate hidden
// ghost template needed, since this *is* the block: the drag ghost is just a
// clone of it).
import { computed } from 'vue';
import type { BlockNode } from '../graph/blockGraph';
import { isCapType, isEntryTriggerType, isHeaderType, shapeFor } from '../graph/shapeRegistry';
import { getPaletteBlockField } from '../graph/fieldRegistry';
import { beginPaletteDrag } from './canvasDrag';
import { getHost } from './host';

const props = defineProps<{ type: string; instruction: BlockNode; variantId?: string }>();

const shape = computed(() => shapeFor(props.type));
const isWrap = computed(() => shape.value?.kind === 'wrap');
const fieldComponent = computed(() => getPaletteBlockField(props.type));
const typeIcon = computed(() => shape.value?.icon);

function onPointerDown(e: PointerEvent) {
  const target = e.target as Element | null;
  if (target?.closest?.('input, select, textarea, button, .dd-trigger, .dd-option')) return;
  if (target instanceof HTMLElement && target.isContentEditable) return;
  const el = e.currentTarget as HTMLElement;
  beginPaletteDrag(e, props.type, el.cloneNode(true) as HTMLElement, props.variantId);
}

function onContextMenu(e: MouseEvent) {
  e.preventDefault();
  getHost().onPaletteInstructionContextMenu?.(e, props.type, props.variantId);
}
</script>

<template>
  <div v-if="isWrap" class="instruction-row instruction-row-wrap palette-prefab" @pointerdown="onPointerDown" @contextmenu="onContextMenu">
    <div class="wrap-head-line">
      <component :is="typeIcon" class="instruction-type-icon-inline" />
      <component :is="fieldComponent" :instruction="instruction" part="head" />
    </div>
    <component :is="fieldComponent" :instruction="instruction" part="body" />
    <div class="wrap-foot-bar" />
  </div>
  <div
    v-else
    class="instruction-row palette-prefab"
    :class="{ 'instruction-row-when-ran': isEntryTriggerType(type), 'instruction-row-header': isHeaderType(type), 'instruction-row-cap': isCapType(type) }"
    @pointerdown="onPointerDown"
    @contextmenu="onContextMenu"
  >
    <div class="instruction-shape">
      <component :is="typeIcon" v-if="!isHeaderType(type)" class="instruction-type-icon" />
      <div class="instruction-content">
        <component :is="fieldComponent" :instruction="instruction" />
      </div>
    </div>
  </div>
</template>
