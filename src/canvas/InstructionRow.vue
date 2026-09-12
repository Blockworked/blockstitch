<script setup lang="ts">
import { computed, ref } from 'vue';
import type { BlockNode, NodePath } from '../graph/blockGraph';
import { isCapType, isEntryTriggerType, isHeaderType, shapeFor } from '../graph/shapeRegistry';
import { getBlockField } from '../graph/fieldRegistry';
import { beginPickup } from './canvasDrag';
import { getHost } from './host';

const props = defineProps<{ strandId: string; path: NodePath; instruction: BlockNode; isFirst?: boolean; isLast?: boolean }>();

// Every ordinary (non-wrap) instruction type renders as one puzzle-piece row
// with its registered field component filling `.instruction-content`. A
// wrap/C-block type is a stack of independently-shaped bars around a hollow
// mouth (see the host's `.instruction-row-wrap` styling), rendered
// separately below — its field component renders twice, once with
// `part="head"` and once with `part="body"`.
const shape = computed(() => shapeFor(props.instruction.type));
const isWrap = computed(() => shape.value?.kind === 'wrap');
// The foot bar's top notch receives the bottom bump of whichever row ends
// up last in the *last* slot (for If-Else, the else arm; every other wrap
// type has only one slot). A cap-type row there has no bump to receive —
// see `.wrap-bar-flat-notch` in the theme CSS for why that leaves an
// unfilled hole unless this class steps in to trace a flat top instead.
const footNotchFlat = computed(() => {
  const slots = shape.value?.getSlots?.(props.instruction);
  const lastSlot = slots?.[slots.length - 1];
  const lastRow = lastSlot?.[lastSlot.length - 1];
  return !!lastRow && isCapType(lastRow.type, lastRow);
});
const fieldComponent = computed(() => getBlockField(props.instruction.type));
const typeIcon = computed(() => shape.value?.icon);
const showIcon = computed(() => !isHeaderType(props.instruction.type));
const index = computed(() => props.path[props.path.length - 1]?.index ?? 0);

const isRecordingTarget = computed(
  () => !!props.isFirst && props.path.length === 1 && (getHost().isRecordingTarget?.(props.strandId, props.path) ?? false),
);

// Walks up from `el` toward (but never past) `boundary`, looking for an
// ancestor matching `selector`. Unlike a plain `el.closest(selector)`, this
// never looks *above* the row whose own listener is running the check — a
// wrap block's outer container wraps every nested block sitting in its own
// mouth, and a plain `.closest('.wrap-mouth')` from any of those nested
// blocks' own handlers would also find whatever mouth belongs to an
// *ancestor* wrap block further up the tree (e.g. a wrap block nested inside
// another), incorrectly treating a click/hover on the inner block's own
// content as if it landed inside a mouth at all.
function closestWithin(el: Element | null, selector: string, boundary: Element): Element | null {
  let cur = el;
  while (cur && cur !== boundary) {
    if (cur.matches(selector)) return cur;
    cur = cur.parentElement;
  }
  return null;
}

function onRowPointerDown(e: PointerEvent) {
  const target = e.target as Element | null;
  if (target?.closest?.('input, select, textarea, button, .dd-trigger, .dd-option')) return;
  if (target instanceof HTMLElement && target.isContentEditable) return;
  const currentTarget = e.currentTarget as Element;
  // Wrap blocks listen on their own outer container, not just
  // `.wrap-head-line`, so the whole outline (head line, mid bar, foot bar,
  // spine) is grabbable. But that container also wraps every nested block
  // sitting in its mouth, and pointerdown bubbles, so without this guard,
  // picking up a nested block — or even clicking genuinely empty space
  // inside a mouth — would *also* pick up the outer wrap block.
  // `.wrap-mouth`'s own box is `pointer-events: none` (only its spine
  // pseudo-elements opt back into `auto`), so a real nested `.instruction-
  // row` is only ever reached as `target` when the pointer is actually over
  // that row's own content — the spine hits `.wrap-mouth` itself as
  // `target`, not a descendant.
  const mouth = target ? closestWithin(target, '.wrap-mouth', currentTarget) : null;
  if (mouth && target !== mouth) return;
  // Genuinely empty mouth space (no spine, no nested row under the pointer)
  // has nothing pointer-events:auto to hit at all, so the browser falls all
  // the way through to the nearest ancestor that still accepts pointer
  // events — this row itself, meaning `target` ends up as the *same*
  // element the listener is bound to instead of any real descendant.
  if (target === currentTarget) return;
  beginPickup(e, props.strandId, props.path);
}

function onRowContextMenu(e: MouseEvent) {
  // Same reasoning as onRowPointerDown's guards above — right-clicking a
  // nested block, or genuinely hollow space inside a mouth, shouldn't open
  // the outer wrap block's own menu.
  const target = e.target as Element | null;
  const currentTarget = e.currentTarget as Element;
  const mouth = target ? closestWithin(target, '.wrap-mouth', currentTarget) : null;
  if (mouth && target !== mouth) return;
  if (target === currentTarget) return;
  getHost().onBlockContextMenu?.(e, props.strandId, props.path);
}

// Whether the spine (the visual strip along the left edge of a mouth,
// painted by `.wrap-mouth`'s own pseudo-elements) is currently hovered, so
// `.wrap-spine-hover` below can re-theme the whole block the same way
// hovering the head/mid/foot bars already does. This can't be expressed as a
// plain `:has(.wrap-mouth:hover)` in CSS: `:hover` on `.wrap-mouth` is *also*
// true whenever a nested block sitting inside it is hovered (CSS hover state
// bubbles up through every ancestor regardless of `pointer-events`), and
// there's no way to carve that back out in pure CSS. Tracking it in JS
// instead sidesteps the restriction entirely.
const spineHovered = ref(false);

function onRowPointerOver(e: PointerEvent) {
  const target = e.target as Element | null;
  // A spine hit always lands exactly *on* its `.wrap-mouth` element — it's
  // painted by that element's own pseudo-elements, never a descendant — so
  // this doesn't need `closestWithin`'s ancestor walk, just a direct match.
  // That distinction matters for a nested wrap block: the walk finds the
  // *nearest* `.wrap-mouth` between target and boundary regardless of
  // whose it is, so hovering the *inner* block's own spine (target IS the
  // inner mouth) would otherwise also satisfy the *outer* row's check, since
  // the inner mouth is still found somewhere between target and the outer
  // boundary. Requiring `target.parentElement === currentTarget` pins the
  // match to *this* row's own direct mouth specifically.
  spineHovered.value = !!target && target.classList.contains('wrap-mouth') && target.parentElement === e.currentTarget;
}

function onRowPointerLeave() {
  spineHovered.value = false;
}
</script>

<template>
  <div
    v-if="isWrap"
    class="instruction-row instruction-row-wrap"
    :class="{ 'row-first': isFirst, 'row-last': isLast, 'wrap-spine-hover': spineHovered }"
    :data-index="index"
    :data-instr-id="instruction.id"
    @pointerdown="onRowPointerDown"
    @contextmenu.prevent.stop="onRowContextMenu"
    @pointerover="onRowPointerOver"
    @pointerleave="onRowPointerLeave"
  >
    <div class="wrap-head-line">
      <component :is="typeIcon" class="instruction-type-icon-inline" />
      <component :is="fieldComponent" part="head" :strand-id="strandId" :path="path" :instruction="instruction" />
    </div>
    <component :is="fieldComponent" part="body" :strand-id="strandId" :path="path" :instruction="instruction" />
    <div class="wrap-foot-bar" :class="{ 'wrap-bar-flat-notch': footNotchFlat }" />
  </div>
  <div
    v-else
    class="instruction-row"
    :class="{ 'row-first': isFirst, 'row-last': isLast, 'instruction-row-when-ran': isEntryTriggerType(instruction.type), 'instruction-row-header': isHeaderType(instruction.type), 'instruction-row-cap': isCapType(instruction.type, instruction) }"
    :data-index="index"
    :data-instr-id="instruction.id"
    @pointerdown="onRowPointerDown"
    @contextmenu.prevent.stop="onRowContextMenu"
  >
    <div class="instruction-shape">
      <span v-if="isRecordingTarget" class="recording-target-dot" title="Recording target" />
      <component :is="typeIcon" v-if="showIcon" class="instruction-type-icon" />
      <div class="instruction-content">
        <component :is="fieldComponent" :strand-id="strandId" :path="path" :instruction="instruction" />
      </div>
    </div>
  </div>
</template>
