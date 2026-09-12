<script setup lang="ts">
// A sidebar "prefab" for a value block (a number/text literal, any
// registered operator, or a `Var:<name>`/`Param:<name>` reference) — same
// boxed `.value-card-shape` appearance a real floating/operator ValueBlock
// gets. Editable in place (the host owns the actual persisted draft via
// `value`/`update:value`), but — like PaletteInstructionBlock — never
// recurses and never registers as a value-drop target, so nothing can be
// dropped into it; the whole sidebar already refuses value drops outright
// (`isOverSidebar` in canvas/canvasDrag.ts), so this simply never opts into
// that machinery.
import { computed } from 'vue';
import { specForKind } from '../graph/operatorRegistry';
import { beginValuePaletteDrag, paletteEvalPreview } from '../values/valueDrag';
import { getHost } from './host';
import AutosizeInput from '../ui/AutosizeInput.vue';
import AppDropdown from '../ui/AppDropdown.vue';
import type { ValueNode } from '../values/valueNode';

// `value` is only meaningful for the editable 'Number'/'Text'/operator
// cases below — a `Var:`/`Param:` reference just renders its name and never
// reads it, so callers rendering only those kinds may omit it. `boolOverride`
// lets a caller declare a `Param:<name>` prefab boolean-shaped (a custom
// block's own header row, e.g., knows each param's declared type directly
// from its `BlockDef` — no operator spec exists for it to fall back on, so
// `specForKind` alone would never see it as boolean). `dragKind`, if given,
// is what's actually threaded into the drag/drop machinery (and so into
// `resolveFreshValue`/`createFloatingValue`'s `sourceKind`) instead of
// `kind` — lets a caller pack extra host-only context into the string used
// to build/track the dragged value (e.g. which block a header's `Param:`
// oval belongs to) without that context leaking into `kind`'s own display
// role (`kind.slice(...)` above).
const props = defineProps<{ kind: string; value?: ValueNode; boolOverride?: boolean; dragKind?: string }>();
const emit = defineEmits<{ 'update:value': [ValueNode] }>();

const spec = computed(() => specForKind(props.kind));
const isBool = computed(() => props.boolOverride ?? spec.value?.resultType === 'bool');
const args = computed(() => (props.value?.kind === 'Op' ? props.value.args : []));

// Set only when this exact prefab was last clicked (not dragged) — see
// values/valueDrag.ts's onPointerUp/previewClickedPaletteValue. Keyed by
// whichever string actually went into the drag/click machinery (dragKind,
// if given — see beginValuePaletteDrag below), not the display-only `kind`.
const preview = computed(() => (paletteEvalPreview.value?.kind === (props.dragKind ?? props.kind) ? paletteEvalPreview.value : null));

function onPointerDown(e: PointerEvent) {
  if ((e.target as Element | null)?.closest?.('input, .dd')) return;
  // Stop the pointerdown from also reaching an ancestor InstructionRow —
  // otherwise its onRowPointerDown arms a whole-block pickup drag at the
  // same time this arms the value-drag machinery, and both fire together.
  // Mirrors ValueBlock.vue's onPointerDown, which does the same for the
  // same reason.
  e.stopPropagation();
  beginValuePaletteDrag(e, props.dragKind ?? props.kind, e.currentTarget as HTMLElement);
}

function onContextMenu(e: MouseEvent) {
  e.preventDefault();
  if (props.kind.startsWith('Var:')) {
    getHost().onVariableContextMenu?.(e, props.kind.slice(4));
  } else {
    getHost().onPaletteValueContextMenu?.(e, props.kind);
  }
}

function onNumberInput(v: string) {
  const n = Number(v);
  if (v.trim() !== '' && !isNaN(n)) emit('update:value', { kind: 'Number', value: n });
}
function onTextInput(v: string) {
  emit('update:value', { kind: 'Text', value: v });
}
function onArgInput(index: number, v: string) {
  if (!spec.value || props.value?.kind !== 'Op') return;
  const nextArgs = [...props.value.args];
  if (spec.value.argTypes[index] === 'number') {
    const n = Number(v);
    if (v.trim() !== '' && !isNaN(n)) nextArgs[index] = { kind: 'Number', value: n };
  } else {
    nextArgs[index] = { kind: 'Text', value: v };
  }
  emit('update:value', { ...props.value, args: nextArgs });
}
function argText(arg: ValueNode): string {
  return arg.kind === 'Number' ? String(arg.value) : arg.kind === 'Text' ? arg.value : '';
}
</script>

<template>
  <span
    class="value-block palette-prefab"
    :class="isBool ? 'value-card-shape-bool' : 'value-card-shape'"
    @pointerdown="onPointerDown"
    @contextmenu="onContextMenu"
  >
    <template v-if="kind === 'Number'">
      <AutosizeInput :model-value="value?.kind === 'Number' ? String(value.value) : '0'" :min-chars="2" @update:model-value="onNumberInput" />
    </template>
    <template v-else-if="kind === 'Text'">
      <AutosizeInput :model-value="value?.kind === 'Text' ? value.value : ''" :min-chars="4" placeholder="text" @update:model-value="onTextInput" />
    </template>
    <template v-else-if="kind.startsWith('Var:')">
      <span class="value-op">{{ kind.slice(4) }}</span>
    </template>
    <template v-else-if="kind.startsWith('Param:')">
      <span class="value-op">{{ kind.slice(6) }}</span>
    </template>
    <template v-else-if="spec">
      <span v-if="spec.prefix" class="value-op">{{ spec.prefix }}</span>
      <template v-for="(arg, i) in args" :key="i">
        <span v-if="i > 0 && spec.infix" class="value-op">{{ spec.infix }}</span>
        <AppDropdown
          v-if="spec.enumArg?.index === i"
          :options="spec.enumArg.options"
          :model-value="argText(arg)"
          class-name="dd-compact"
          @update:model-value="v => onArgInput(i, v)"
        />
        <!-- Boolean slots have no editable palette leaf — a static blank
             hexagon placeholder, same as a real unfilled boolean slot. -->
        <span v-else-if="spec.argTypes[i] === 'bool'" class="value-block value-hex-blank">
          <span class="value-op value-hex-blank-spacer">&nbsp;</span>
        </span>
        <AutosizeInput
          v-else
          :model-value="argText(arg)"
          :min-chars="spec.argTypes[i] === 'text' ? 4 : 1"
          :placeholder="spec.argTypes[i] === 'text' ? 'text' : undefined"
          @update:model-value="v => onArgInput(i, v)"
        />
      </template>
      <span v-if="spec.suffix" class="value-op">{{ spec.suffix }}</span>
    </template>
    <span v-if="preview" class="value-eval-tooltip" :class="{ 'value-eval-tooltip-error': preview.error }">{{ preview.text }}</span>
  </span>
</template>
