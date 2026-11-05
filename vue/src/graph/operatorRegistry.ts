// Registry of value-expression operators (Add, Join, comparisons, ...) — the
// host registers its own concrete operator table at startup; this module
// only owns the generic shape (arity, arg types, prefix/infix rendering,
// optional fixed-dropdown arg) and lookup helpers.
export interface OperatorKindSpec {
  /** The palette/value "kind" string this spec answers to (e.g. `'Add'`,
   * `'Join3'` — distinct from `op` since two kinds can share one `op`, see
   * Join/Join3 in the host's table). */
  kind: string;
  /** The operator id carried on the wire/serialized value tree. */
  op: string;
  arity: number;
  /** One entry per arg, in order — lets an operator mix types. */
  argTypes: ('number' | 'text' | 'bool')[];
  /** What this operator's result "is" — drives shape (booleans render as a
   * hexagon, see ValueBlock.vue). */
  resultType: 'number' | 'text' | 'bool';
  /** Rendered before the first arg (word-phrase operators). */
  prefix?: string;
  /** Rendered between each consecutive pair of args. */
  infix?: string;
  /** Rendered after the final argument. */
  suffix?: string;
  /** If set, `args[enumArg.index]` is a fixed dropdown choice, not a
   * draggable value slot. */
  enumArg?: { index: number; options: { value: string; label: string }[] };
}

const specsByKind = new Map<string, OperatorKindSpec>();
const specsByOp = new Map<string, OperatorKindSpec>();

/** Registers one operator spec — call once per spec at host startup. */
export function registerOperator(spec: OperatorKindSpec): void {
  specsByKind.set(spec.kind, spec);
  // First registration for a given `op` wins (mirrors the host's own
  // "labels match across arities" contract, e.g. Join/Join3 both answer `op`
  // lookups as whichever was registered first).
  if (!specsByOp.has(spec.op)) specsByOp.set(spec.op, spec);
}

export function registerOperators(specs: OperatorKindSpec[]): void {
  specs.forEach(registerOperator);
}

export function specForKind(kind: string): OperatorKindSpec | undefined {
  return specsByKind.get(kind);
}

/** An existing operator node only carries `op`, not which palette kind built
 * it — returns whichever spec was first registered for that `op`. */
export function specForOp(op: string): OperatorKindSpec | undefined {
  return specsByOp.get(op);
}

export function labelForOp(op: string): Pick<OperatorKindSpec, 'prefix' | 'infix' | 'suffix'> | undefined {
  const spec = specForOp(op);
  return spec && { prefix: spec.prefix, infix: spec.infix, suffix: spec.suffix };
}

export function allOperators(): OperatorKindSpec[] {
  return [...specsByKind.values()];
}
