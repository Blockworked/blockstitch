// What a block *type* looks like structurally — a plain single-line block
// ('stack'), an entry-point trigger with nothing allowed above it ('header'),
// a block nothing may ever be stacked below ('cap'), or a C-block wrapping
// one or more nested instruction lists ('wrap'). The host registers one of
// these per instruction type at startup; every generic tree-navigation
// helper in blockGraph.ts (and the drag/snap engine in canvas/canvasDrag.ts)
// reads shape from here instead of hardcoding type names.
import type { Component } from 'vue';
import type { BlockNode } from './blockGraph';

export interface BlockShapeDescriptor<TNode extends BlockNode = BlockNode> {
  kind: 'stack' | 'header' | 'cap' | 'wrap';
  /** Icon shown in the block's row (and, for a wrap block, its head line). */
  icon?: Component;
  /** Only meaningful for `kind: 'header'` — the subset of headers that are
   * "entry point" triggers (vs. e.g. a custom block's own definition header)
   * and get a quiet accent tint. */
  isEntryTrigger?: boolean;
  /** Only meaningful for `kind: 'wrap'` — this node's nested instruction
   * lists, in slot order (index 0 = slot 0, etc). Read-only navigation. */
  getSlots?(node: TNode): TNode[][];
  /** Only meaningful for `kind: 'wrap'` — returns a copy of `node` with every
   * slot list replaced by `fn(originalSlot, slotIndex)`. Used to regenerate
   * ids through a nested tree without the generic code needing to know each
   * wrap type's actual field names (`body`/`then_body`/`else_body`/...). */
  mapSlots?(node: TNode, fn: (slot: TNode[], slotIndex: number) => TNode[]): TNode;
  /** Only meaningful for `kind: 'stack'` — lets ONE registered type act as
   * `cap` (no bottom notch) for some instances and not others, based on the
   * node's own data. A static `kind: 'cap'` registration can't express this,
   * since every instance of a type shares the single registry entry — a host
   * whose custom blocks can each independently choose "ends the stack" (e.g.
   * Blockwork's `CallBlock`, shared by every custom block regardless of
   * which one it calls) needs this instead. `isCapType` consults it only
   * when a `node` is given; a type-only lookup falls back to the static
   * `kind === 'cap'` check alone. */
  isCap?(node: TNode): boolean;
}

const registry = new Map<string, BlockShapeDescriptor<any>>();

/** Registers the shape for one block type — call once per type at host
 * startup. Re-registering the same type overwrites the previous entry. */
export function registerBlockShape<TNode extends BlockNode>(type: string, shape: BlockShapeDescriptor<TNode>): void {
  registry.set(type, shape);
}

export function shapeFor(type: string): BlockShapeDescriptor | undefined {
  return registry.get(type);
}

export function isHeaderType(type: string): boolean {
  return shapeFor(type)?.kind === 'header';
}

/** `node`, when given, additionally consults that type's `isCap` predicate
 * (see `BlockShapeDescriptor`) so a single registered type can be `cap` for
 * only some of its instances — omit it for a plain static type-only check. */
export function isCapType(type: string, node?: BlockNode): boolean {
  const shape = shapeFor(type);
  if (!shape) return false;
  if (shape.kind === 'cap') return true;
  return node !== undefined && shape.isCap?.(node) === true;
}

export function isWrapType(type: string): boolean {
  return shapeFor(type)?.kind === 'wrap';
}

export function isEntryTriggerType(type: string): boolean {
  const shape = shapeFor(type);
  return shape?.kind === 'header' && !!shape.isEntryTrigger;
}

export function iconFor(type: string): Component | undefined {
  return shapeFor(type)?.icon;
}

/** Test-only/dev-only: clears every registered shape. Not used by app code. */
export function _clearBlockShapes(): void {
  registry.clear();
}
