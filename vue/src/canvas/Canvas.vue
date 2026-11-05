<script setup lang="ts">
import { onMounted, watch } from 'vue';
import { getHost } from './host';
import { attachDragListeners, positionCanvas, resetCanvasView, zoomInCanvas, zoomOutCanvas } from './canvasDrag';
import { attachValueDragListeners } from '../values/valueDrag';
import StrandCard from './StrandCard.vue';
import FloatingValueCard from '../values/FloatingValueCard.vue';
import CommentCard from '../comments/CommentCard.vue';

// Only genuine empty-space right-clicks reach here — InstructionRow's own
// contextmenu handler calls stopPropagation for right-clicks on a block.
function onCanvasContextMenu(e: MouseEvent) {
  getHost().onCanvasContextMenu?.(e);
}

onMounted(() => {
  attachDragListeners();
  attachValueDragListeners();
  positionCanvas(getHost().getDocument()?.id);
});

// DOM geometry (bounding box measurement + card left/top/canvas
// width/height/transform) is an inherently two-pass, DOM-measurement
// operation — it needs to read the just-rendered, unstyled DOM
// (offsetWidth/offsetHeight), which Vue's reactivity graph has no visibility
// into. So this runs as a plain post-patch pass rather than a computed/:style
// binding: `flush: 'post'` guarantees the v-for'd .strand-card/
// .value-floating-card elements already exist in the DOM when it runs.
watch(
  () => {
    const doc = getHost().getDocument();
    return [doc?.strands, doc?.floating_values, doc?.comments];
  },
  () => positionCanvas(getHost().getDocument()?.id),
  { flush: 'post', deep: true },
);
</script>

<template>
  <div class="canvas-wrap">
    <div class="canvas-scroll" id="canvas-scroll" @contextmenu.prevent="onCanvasContextMenu">
      <div class="canvas-sizer" id="canvas-sizer">
        <div class="canvas-inner" id="canvas-inner">
          <svg id="comment-connector-layer" class="comment-connector-layer"></svg>
          <StrandCard v-for="strand in getHost().getDocument()?.strands ?? []" :key="strand.id" :strand="strand" />
          <FloatingValueCard
            v-for="fv in getHost().getDocument()?.floating_values ?? []"
            :key="fv.id"
            :floating-value="fv"
          />
          <CommentCard
            v-for="comment in getHost().getDocument()?.comments ?? []"
            :key="comment.id"
            :comment="comment"
          />
        </div>
      </div>
    </div>
    <div class="canvas-zoom-controls">
      <button type="button" class="canvas-zoom-btn" title="Zoom in" @click="zoomInCanvas">
        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
          <circle cx="11" cy="11" r="7"></circle>
          <line x1="11" y1="8" x2="11" y2="14"></line>
          <line x1="8" y1="11" x2="14" y2="11"></line>
          <line x1="21" y1="21" x2="16.65" y2="16.65"></line>
        </svg>
      </button>
      <button type="button" class="canvas-zoom-btn" title="Zoom out" @click="zoomOutCanvas">
        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
          <circle cx="11" cy="11" r="7"></circle>
          <line x1="8" y1="11" x2="14" y2="11"></line>
          <line x1="21" y1="21" x2="16.65" y2="16.65"></line>
        </svg>
      </button>
      <button type="button" class="canvas-zoom-btn" title="Reset view" @click="resetCanvasView">
        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
          <path d="M3 12a9 9 0 1 0 9-9 9.75 9.75 0 0 0-6.74 2.74L3 8"></path>
          <path d="M3 3v5h5"></path>
        </svg>
      </button>
    </div>
    <slot name="overlay" />
    <slot name="context-menu" />
  </div>
</template>
