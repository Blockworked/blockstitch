// Generic addressing/navigation over a tree of block instructions — the
// host's concrete instruction type only needs an `id`/`type` pair (see
// `BlockNode`); everything about *where its nested bodies live* comes from
// the shape registry (shapeRegistry.ts) instead of hardcoded field names, so
// this module never needs to know the host's actual type union.
import { shapeFor } from './shapeRegistry';

export interface BlockNode {
  id: string;
  type: string;
}

// Not exported from index.ts — canvas/host.ts's `StrandLike` (a superset,
// with x/y) is the one host code should reach for; this is just the minimal
// shape the pure tree-navigation helpers below actually need.
interface MinimalStrand<TNode extends BlockNode = BlockNode> {
  id: string;
  instructions: TNode[];
}

// One step of a NodePath — `index` into the current instruction list, and
// (for every step but the last) which nested slot of that instruction to
// descend into next (0 for a wrap block's first body, 1 for its second,
// etc). The last step's `slot` is omitted.
export interface PathStep {
  index: number;
  slot?: number;
}

/** Addresses one instruction, possibly nested inside wrap-block bodies. */
export type NodePath = PathStep[];

/** The common case: a top-level instruction at `index` in a strand's own
 * instruction list — what every non-nested call site should pass. */
export function topLevelPath(index: number): NodePath {
  return [{ index }];
}

/** Resolves `basePath` against a strand to the (possibly nested) instruction
 * list it addresses — a strand's own top-level list for `basePath: []`, or a
 * wrap block's nested slot for anything longer. */
export function resolveInstructionList<TNode extends BlockNode>(
  strand: MinimalStrand<TNode> | null | undefined,
  basePath: PathStep[],
): TNode[] {
  let list: TNode[] | undefined = strand?.instructions;
  for (const step of basePath) {
    const ins = list?.[step.index];
    if (!ins) return [];
    const shape = shapeFor(ins.type);
    if (shape?.kind === 'wrap' && shape.getSlots && step.slot != null) {
      list = shape.getSlots(ins)[step.slot] as TNode[] | undefined;
    } else {
      return [];
    }
  }
  return list ?? [];
}

/** The single instruction `path` addresses, or `null` if any step along the
 * way doesn't resolve (e.g. stale state mid-edit). */
export function resolveInstructionAt<TNode extends BlockNode>(
  strand: MinimalStrand<TNode> | null | undefined,
  path: NodePath,
): TNode | null {
  if (path.length === 0) return null;
  const list = resolveInstructionList(strand, path.slice(0, -1));
  return list[path[path.length - 1].index] ?? null;
}

/** The path of the instruction immediately after `path`, in the same body
 * list — e.g. for "insert a duplicate right after this block." */
export function nextSiblingPath(path: NodePath): NodePath {
  const steps = [...path];
  const last = steps[steps.length - 1];
  steps[steps.length - 1] = { ...last, index: last.index + 1 };
  return steps;
}

/** The base path for a wrap block's own nested slot `slot` — `path` is that
 * instruction's own address (its last step has no `slot`, since nothing
 * follows it yet); this stamps `slot` onto that last step, so a list
 * rendering that slot's body can append its own children's indices after it. */
export function bodyBasePath(path: NodePath, slot: number): NodePath {
  const steps = [...path];
  const last = steps[steps.length - 1];
  steps[steps.length - 1] = { ...last, slot };
  return steps;
}

/** Structural equality for two NodePaths — used wherever a path is compared
 * instead of a bare index. */
export function pathsEqual(a: NodePath | null | undefined, b: NodePath | null | undefined): boolean {
  if (a == null || b == null) return a === b;
  return a.length === b.length && a.every((step, i) => step.index === b[i].index && step.slot === b[i].slot);
}

/** A fresh id for a brand-new instruction/comment/value — falls back to a
 * non-crypto id in a webview without `crypto.randomUUID`. */
export function newId(): string {
  return crypto.randomUUID?.() ?? `i${Math.random().toString(36).slice(2)}`;
}

/** Deep-clones an instruction (and, for a wrap block, everything nested in
 * every slot) with a fresh id at every level, via the shape registry's
 * `mapSlots` — duplicating or pasting an existing instruction must never
 * leave two live instructions sharing an id. */
export function regenerateInstructionIds<TNode extends BlockNode>(ins: TNode): TNode {
  const copy: TNode = { ...ins, id: newId() };
  const shape = shapeFor(copy.type);
  if (shape?.kind === 'wrap' && shape.mapSlots) {
    return shape.mapSlots(copy, slot => slot.map(n => regenerateInstructionIds(n))) as TNode;
  }
  return copy;
}

// ── Value-tree addressing ───────────────────────────────────────────────────
// Addresses a single value-expression node: inside an instruction field, or a
// floating canvas block, at `path` within that root.
export type ValueLocation =
  | { kind: 'Field'; strand_id: string; index: NodePath; field_id: string; path: number[] }
  | { kind: 'Floating'; floating_id: string; path: number[] };

export function fieldLocation(strandId: string, instrPath: NodePath, fieldId: string): ValueLocation {
  return { kind: 'Field', strand_id: strandId, index: instrPath, field_id: fieldId, path: [] };
}

/** Structural equality for two ValueLocations. */
export function locationsEqual(a: ValueLocation, b: ValueLocation): boolean {
  if (a.kind !== b.kind) return false;
  if (a.path.length !== b.path.length || !a.path.every((p, i) => p === b.path[i])) return false;
  if (a.kind === 'Field' && b.kind === 'Field') {
    return a.strand_id === b.strand_id && pathsEqual(a.index, b.index) && a.field_id === b.field_id;
  }
  if (a.kind === 'Floating' && b.kind === 'Floating') return a.floating_id === b.floating_id;
  return false;
}
