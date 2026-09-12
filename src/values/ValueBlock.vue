<script setup lang="ts">
// Recursive renderer for a `ValueNode` expression tree — a number, a piece of
// text, or an operator block combining its nested `args` into `ValueBlock`s
// (rendered as `prefix arg1 infix arg2[ infix arg3 ...]`, labels looked up
// from the operator registry — no parens). An operator node, a leaf parked
// at the root of a `Floating` location (a standalone canvas block with
// nothing else to grab it by), or a leaf that landed in its slot by being
// dropped there as its own block (tracked ephemerally by valueDrag.ts's
// capsuleLocations, since the value tree itself can't tell a dropped-in leaf
// apart from an ordinary one) renders as an actual bordered,
// pickup-draggable block (`.value-card-shape`); an ordinary leaf sitting in
// a field — never dragged, just typed into — is just its bare input, not
// draggable — see `boxed` below and `onPointerDown`'s gate on it. Changing
// what's in a slot is done by dragging a different block from the sidebar's
// "Operator" section (or an existing block) onto it, via valueDrag.ts —
// there's no in-place kind picker here. `location` addresses this node; a
// `<script setup>` SFC can reference itself by filename, so no explicit
// self-registration is needed for the recursion below. Clicking (not
// dragging) an operator block samples-evaluates just that node and shows the
// result in a small tooltip — see `preview` below and valueDrag.ts's
// onPointerUp/previewClickedOperator.
import { computed, ref, watchEffect } from 'vue';
import { getHost } from '../canvas/host';
import { locationsEqual } from '../graph/blockGraph';
import type { ValueLocation } from '../graph/blockGraph';
import { beginValuePickup, dragReveal, evalPreview, isCapsuleLocation } from './valueDrag';
import { labelForOp, specForOp } from '../graph/operatorRegistry';
import AutosizeInput from '../ui/AutosizeInput.vue';
import AppDropdown from '../ui/AppDropdown.vue';
import type { ValueNode } from './valueNode';

const props = defineProps<{
  location: ValueLocation;
  value: ValueNode;
  placeholder?: string;
}>();

const rootEl = ref<HTMLElement | null>(null);

// While this exact slot is the origin of an in-flight value drag, show what
// take_value will actually leave behind instead of the (about-to-be-taken)
// real value — see valueDrag.ts's dragReveal.
const displayValue = computed(() =>
  dragReveal.value && locationsEqual(dragReveal.value.location, props.location) ? dragReveal.value.value : props.value);

const buf = computed(() => (displayValue.value.kind === 'Number' ? getHost().getInvalidText?.(props.location) ?? null : null));

const label = computed(() => (displayValue.value.kind === 'Op' ? labelForOp(displayValue.value.op) : undefined));

// Set for operators with an `enumArg` (e.g. a case-conversion upper/lowercase
// toggle) — that arg renders as a dropdown bound via editValueField, not a
// nested ValueBlock, since it's a fixed choice rather than a draggable value
// slot.
const enumArg = computed(() => (displayValue.value.kind === 'Op' ? specForOp(displayValue.value.op)?.enumArg : undefined));

// For a `Call` node, pairs each of the block's prototype pieces with the arg
// index it addresses (labels get `null` — nothing to render but text).
// Mirrors labelForOp's role for `Op`, just driven by the host's own dynamic
// block prototype instead of a fixed prefix/infix spec.
const callPieces = computed(() => {
  const v = displayValue.value;
  if (v.kind !== 'Call') return [];
  const pieces = getHost().resolveCallPieces?.(v.block_id);
  if (!pieces) return [];
  let argIndex = 0;
  return pieces.map(piece => (piece.kind === 'Input' ? { piece, argIndex: argIndex++ } : { piece, argIndex: -1 }));
});

function onEnumEdit(step: number, v: string) {
  getHost().backend.editValueField(childLocation(step), v);
}

// Set only for the exact operator node that was last clicked (not dragged)
// — see valueDrag.ts's onPointerUp/previewClickedOperator. Auto-clears
// itself after a timeout, so this just reflects whatever's currently live.
const preview = computed(() =>
  evalPreview.value && locationsEqual(evalPreview.value.location, props.location) ? evalPreview.value : null);

const boxed = computed(() =>
  displayValue.value.kind === 'Op' ||
  displayValue.value.kind === 'Var' ||
  displayValue.value.kind === 'Param' ||
  displayValue.value.kind === 'Call' ||
  (props.location.kind === 'Floating' && props.location.path.length === 0) ||
  isCapsuleLocation(props.location));

// Boolean-producing operators (comparisons, and/or/not, true/false), the
// blank `Bool` leaf a boolean slot defaults to, a `Param` reporter reading a
// boolean-typed custom-block input (ask the host — a bare `Param` node has
// no type of its own, see host.ts's `paramIsBool`), and a `Call` reporter
// invoking a boolean-returning custom block (host.ts's `callIsBool`) all
// render as a hexagon instead of the ordinary rounded capsule — Scratch's
// visual language for "this slot expects a boolean."
const isBool = computed(() =>
  displayValue.value.kind === 'Bool' ||
  (displayValue.value.kind === 'Op' && specForOp(displayValue.value.op)?.resultType === 'bool') ||
  (displayValue.value.kind === 'Param' && (getHost().paramIsBool?.(props.location, displayValue.value.name) ?? false)) ||
  (displayValue.value.kind === 'Call' && (getHost().callIsBool?.(displayValue.value.block_id) ?? false)));

// The hexagon's point angle (a fixed ratio of this block's own height via a
// CSS custom property) stays constant whether the block is a single short
// line or grown tall by a nested arg — CSS alone can't read an element's own
// height for a property on that same element, so this mirrors it into a
// custom property instead. Only tracked while boxed as a hexagon; every
// other shape ignores it entirely.
const blockHeight = ref(25);
watchEffect(onCleanup => {
  if (!isBool.value || !rootEl.value) return;
  const el = rootEl.value;
  const observer = new ResizeObserver(() => {
    blockHeight.value = el.offsetHeight;
  });
  observer.observe(el);
  onCleanup(() => observer.disconnect());
});

function childLocation(step: number): ValueLocation {
  return { ...props.location, path: [...props.location.path, step] } as ValueLocation;
}

function onEdit(text: string) {
  getHost().backend.editValueField(props.location, text);
}

function onPointerDown(e: PointerEvent) {
  if ((e.target as Element | null)?.closest?.('input, .dd')) return;
  // A bare leaf sitting in a field is just its input's padding — nothing to
  // grab, so don't let a click there start an extraction drag; only an
  // actual block (operator, floating root, or a dropped-in capsule leaf —
  // see `boxed`) is pickup-draggable.
  if (!boxed.value) return;
  e.stopPropagation();
  if (rootEl.value) beginValuePickup(e, props.location, props.value, rootEl.value);
}

function onContextMenu(e: MouseEvent) {
  // Same "is this actually a block" gate as the pickup drag above — a bare
  // leaf typed into a field isn't a block to show a menu for, and leaving
  // its native right-click (paste, etc.) alone matters more than a menu.
  if (!boxed.value) return;
  // An operator nested inside another operator is itself a ValueBlock, so
  // without stopping here the event would keep bubbling into the enclosing
  // operator's own listener and reopen the menu for *that* one instead —
  // same reasoning as InstructionRow.vue's onRowContextMenu.
  e.preventDefault();
  e.stopPropagation();
  getHost().onValueContextMenu?.(e, props.location, displayValue.value);
}
</script>

<template>
  <span
    ref="rootEl"
    class="value-block"
    :class="{ 'value-card-shape': boxed && !isBool, 'value-card-shape-bool': boxed && isBool, 'value-hex-blank': !boxed && isBool }"
    :style="isBool ? { '--blockstitch-bh': blockHeight + 'px' } : undefined"
    :data-value-location="JSON.stringify(location)"
    @pointerdown="onPointerDown"
    @contextmenu="onContextMenu"
  >
    <template v-if="displayValue.kind === 'Op'">
      <span v-if="label?.prefix" class="value-op">{{ label.prefix }}</span>
      <template v-for="(arg, i) in displayValue.args" :key="i">
        <span v-if="i > 0 && label?.infix" class="value-op">{{ label.infix }}</span>
        <AppDropdown
          v-if="enumArg?.index === i"
          :options="enumArg.options"
          :model-value="arg.kind === 'Text' ? arg.value : ''"
          class-name="dd-compact"
          @update:model-value="v => onEnumEdit(i, v)"
        />
        <ValueBlock v-else :location="childLocation(i)" :value="arg" />
      </template>
      <span v-if="label?.suffix" class="value-op">{{ label.suffix }}</span>
    </template>
    <template v-else-if="displayValue.kind === 'Var' || displayValue.kind === 'Param'">
      <span class="value-op">{{ displayValue.name }}</span>
    </template>
    <template v-else-if="displayValue.kind === 'Call'">
      <template v-for="(item, i) in callPieces" :key="i">
        <span v-if="item.piece.kind === 'Label'" class="value-op">{{ item.piece.text }}</span>
        <ValueBlock v-else :location="childLocation(item.argIndex)" :value="displayValue.args[item.argIndex]" />
      </template>
    </template>
    <template v-else-if="displayValue.kind === 'Bool'">
      <!-- Invisible spacer, not the empty string — gives the blank hexagon
           the exact same line-height as a real "true"/"false"/comparison
           block's `.value-op` text, so it matches their height instead of
           collapsing to whatever the (content-less) hexagon shape alone
           would be. -->
      <span class="value-op value-hex-blank-spacer">&nbsp;</span>
    </template>
    <template v-else>
      <AutosizeInput
        :model-value="displayValue.kind === 'Number' ? (buf?.text ?? String(displayValue.value)) : displayValue.value"
        :min-chars="2"
        :invalid="buf?.invalid ?? false"
        :placeholder="placeholder"
        @update:model-value="onEdit"
      />
    </template>
    <span v-if="preview" class="value-eval-tooltip" :class="{ 'value-eval-tooltip-error': preview.error }">{{ preview.text }}</span>
  </span>
</template>
