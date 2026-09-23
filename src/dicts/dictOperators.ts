// Dict reporter operators shared by every blockstitch host. The six
// reporters read a document-scoped dict by name; that name arg is a fixed
// dropdown (a plain `Text` leaf), at the second position for `DictValue`
// and the first for the rest. Mirrors blockstitch-core's
// `graph::dicts::dict_reporter_name_index`, which the backend uses for the
// same lookup — keep the two tables in sync.
import type { OperatorKindSpec } from '../graph/operatorRegistry';
import type { ValueNode } from '../values/valueNode';

/** Wire names of the six dict reporters. */
export const DICT_REPORTER_OPS = [
  'DictValue',
  'DictHasKey',
  'DictSize',
  'DictIsEmpty',
  'DictKeys',
  'DictAsJson',
] as const;

export type DictReporterOp = (typeof DICT_REPORTER_OPS)[number];

/** Which arg holds the dict name, by reporter wire name. */
export const DICT_NAME_ARG_INDEX: Partial<Record<string, number>> = {
  DictValue: 1,
  DictHasKey: 0,
  DictSize: 0,
  DictIsEmpty: 0,
  DictKeys: 0,
  DictAsJson: 0,
};

export function isDictReporterOp(op: string): boolean {
  return DICT_NAME_ARG_INDEX[op] !== undefined;
}

export interface DictNameOption {
  value: string;
  label: string;
}

/**
 * The six dict-reporter palette specs, bound to the host's live
 * dict-name choices. `nameOptions`/`emptyOptions` are the reactive arrays
 * from `./dictNames` (kept stable so specs see renames); the `is ... empty?`
 * entry gets its own array only because its phrasing needs a different
 * fallback label when no dicts exist.
 */
export function dictReporterSpecs(
  nameOptions: DictNameOption[],
  emptyOptions: DictNameOption[] = nameOptions,
): OperatorKindSpec[] {
  const dictArg = { options: nameOptions };
  return [
    { kind: 'DictValue', op: 'DictValue', arity: 2, argTypes: ['text', 'text'], resultType: 'text', prefix: 'value', infix: 'in', enumArg: { index: 1, ...dictArg } },
    { kind: 'DictHasKey', op: 'DictHasKey', arity: 2, argTypes: ['text', 'text'], resultType: 'bool', infix: 'has key', enumArg: { index: 0, ...dictArg } },
    { kind: 'DictSize', op: 'DictSize', arity: 1, argTypes: ['text'], resultType: 'number', prefix: 'size of', enumArg: { index: 0, ...dictArg } },
    { kind: 'DictKeys', op: 'DictKeys', arity: 1, argTypes: ['text'], resultType: 'text', prefix: 'keys of', enumArg: { index: 0, ...dictArg } },
    { kind: 'DictAsJson', op: 'DictAsJson', arity: 1, argTypes: ['text'], resultType: 'text', suffix: 'as JSON', enumArg: { index: 0, ...dictArg } },
    { kind: 'DictIsEmpty', op: 'DictIsEmpty', arity: 1, argTypes: ['text'], resultType: 'bool', prefix: 'is', suffix: 'empty?', enumArg: { index: 0, options: emptyOptions } },
  ];
}

function textArgumentIs(value: ValueNode | undefined, name: string): boolean {
  return value?.kind === 'Text' && value.value === name;
}

/** True when a value tree reads dict `name` through any reporter. */
export function valueUsesDict(value: ValueNode, name: string): boolean {
  if (value.kind !== 'Op' && value.kind !== 'Call') return false;
  if (value.kind === 'Op') {
    const nameIndex = DICT_NAME_ARG_INDEX[value.op];
    if (nameIndex !== undefined && textArgumentIs(value.args[nameIndex], name)) return true;
  }
  return value.args.some(arg => valueUsesDict(arg, name)) || valueUsesDict(value.saved, name);
}
