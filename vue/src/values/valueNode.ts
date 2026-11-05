// A small recursive expression tree backing a value block — a number, a
// piece of text, a blank boolean slot, an operator applied to nested `args`,
// a variable/parameter reference, or a call to a user-defined block. This is
// blockstitch's own concrete shape (not a host-supplied generic) because the
// drag/eval-preview machinery genuinely needs to know these cases — but
// `op`/`block_id` are free-form strings, so a host's own operator vocabulary
// (registered via graph/operatorRegistry.ts) and custom-block ids both fit
// through unchanged.
import type { BlockNode } from '../graph/blockGraph';
export type ValueNode =
  | { kind: 'Number'; value: number }
  | { kind: 'Text'; value: string }
  // Bare boolean leaf, no value of its own — the "nothing plugged in here"
  // state of a boolean slot. Renders as a blank hexagon and evaluates false.
  | { kind: 'Bool' }
  // `saved` is the value the operator displaced when it took over the slot —
  // carried along so a host can hand it back if this block is dragged out.
  | { kind: 'Op'; op: string; args: ValueNode[]; saved: ValueNode }
  | { kind: 'Var'; name: string }
  | { kind: 'Param'; name: string }
  | { kind: 'Call'; block_id: string; args: ValueNode[]; branches: BlockNode[][]; saved: ValueNode };

// Narrow return types (a single union member each, not the whole
// `ValueNode`) so a host with its own narrower value-node type — whose `Op`
// variant pins `op` to a specific string-literal union instead of plain
// `string` — can still assign these results directly: `{kind:'Number',...}`
// alone is trivially assignable regardless of how the host's `Op` case
// looks, whereas the full `ValueNode` union would not be.
export function numberValue(value: number): Extract<ValueNode, { kind: 'Number' }> {
  return { kind: 'Number', value };
}

export function textValue(value: string): Extract<ValueNode, { kind: 'Text' }> {
  return { kind: 'Text', value };
}

export function blankBoolValue(): Extract<ValueNode, { kind: 'Bool' }> {
  return { kind: 'Bool' };
}

export function isLeafValue(v: ValueNode): boolean {
  return v.kind === 'Number' || v.kind === 'Text';
}

/** The value a leaf reverts to once an operator/reference occupying a slot
 * is picked up and dragged away — an operator/call's own `saved` payload, or
 * a fresh zero for anything else (mirrors the host's own
 * `apply_value_kind`-style default). */
export function savedOf(v: ValueNode): ValueNode {
  return v.kind === 'Op' || v.kind === 'Call' ? v.saved : numberValue(0);
}

/** Whether clicking (not dragging) an *existing* node is worth
 * sampling-evaluating — only operators and variable references are (not
 * plain literals, params, or a My-Blocks call). */
export function isPreviewableValue(v: ValueNode): boolean {
  return v.kind === 'Op' || v.kind === 'Var';
}

/** Same idea, for a fresh sidebar palette entry addressed by its string
 * `kind` (e.g. `'Add'`, `'Var:x'`, `'Call:<blockId>'`) rather than a real
 * `ValueNode` — only the two plain-literal kinds are excluded. */
export function isPreviewableKind(kind: string): boolean {
  return kind !== 'Number' && kind !== 'Text';
}
