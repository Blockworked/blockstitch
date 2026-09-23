// List reporter operators shared by every blockstitch host. The eight
// reporters read a document-scoped list by name; that name arg is a fixed
// dropdown (a plain `Text` leaf), at the second position except for the
// three below where it is the first. Mirrors blockstitch-core's
// `graph::lists::list_reporter_name_index`, which the backend uses for the
// same lookup — keep the two tables in sync.
import type { OperatorKindSpec } from '../graph/operatorRegistry';
import type { ValueNode } from '../values/valueNode';

/** Wire names of the eight list reporters. */
export const LIST_REPORTER_OPS = [
  'ListItem',
  'ListItemNumber',
  'ListAmount',
  'ListLength',
  'ListContains',
  'ListItemExists',
  'ListIsEmpty',
  'ListAsJson',
] as const;

export type ListReporterOp = (typeof LIST_REPORTER_OPS)[number];

/** Which arg holds the list name, by reporter wire name. */
export const LIST_NAME_ARG_INDEX: Partial<Record<string, number>> = {
  ListItem: 1,
  ListItemNumber: 1,
  ListAmount: 1,
  ListLength: 0,
  ListContains: 0,
  ListItemExists: 1,
  ListIsEmpty: 0,
  ListAsJson: 0,
};

export function isListReporterOp(op: string): boolean {
  return LIST_NAME_ARG_INDEX[op] !== undefined;
}

export interface ListNameOption {
  value: string;
  label: string;
}

/**
 * The eight list-reporter palette specs, bound to the host's live
 * list-name choices. `nameOptions`/`emptyOptions` are the reactive arrays
 * from `./listNames` (kept stable so specs see renames); the `is ... empty?`
 * entry gets its own array only because its phrasing needs a different
 * fallback label when no lists exist.
 */
export function listReporterSpecs(
  nameOptions: ListNameOption[],
  emptyOptions: ListNameOption[] = nameOptions,
): OperatorKindSpec[] {
  const listArg = { options: nameOptions };
  return [
    { kind: 'ListItem', op: 'ListItem', arity: 2, argTypes: ['number', 'text'], resultType: 'text', prefix: 'item', infix: 'of', enumArg: { index: 1, ...listArg } },
    { kind: 'ListItemNumber', op: 'ListItemNumber', arity: 2, argTypes: ['text', 'text'], resultType: 'number', prefix: 'item # of', infix: 'in', enumArg: { index: 1, ...listArg } },
    { kind: 'ListAmount', op: 'ListAmount', arity: 2, argTypes: ['text', 'text'], resultType: 'number', prefix: 'amount of', infix: 'in', enumArg: { index: 1, ...listArg } },
    { kind: 'ListLength', op: 'ListLength', arity: 1, argTypes: ['text'], resultType: 'number', prefix: 'length of', enumArg: { index: 0, ...listArg } },
    { kind: 'ListContains', op: 'ListContains', arity: 2, argTypes: ['text', 'text'], resultType: 'bool', infix: 'contains', enumArg: { index: 0, ...listArg } },
    { kind: 'ListItemExists', op: 'ListItemExists', arity: 2, argTypes: ['number', 'text'], resultType: 'bool', prefix: 'item', infix: 'exists in', enumArg: { index: 1, ...listArg } },
    { kind: 'ListIsEmpty', op: 'ListIsEmpty', arity: 1, argTypes: ['text'], resultType: 'bool', prefix: 'is', suffix: 'empty?', enumArg: { index: 0, options: emptyOptions } },
    { kind: 'ListAsJson', op: 'ListAsJson', arity: 1, argTypes: ['text'], resultType: 'text', suffix: 'as JSON', enumArg: { index: 0, ...listArg } },
  ];
}

/** Default `Number` for the `item (n) of ...` index slots, which are 1-based. */
export function isOneBasedListIndexArg(kind: string, index: number): boolean {
  return (kind === 'ListItem' || kind === 'ListItemExists') && index === 0;
}

function textArgumentIs(value: ValueNode | undefined, name: string): boolean {
  return value?.kind === 'Text' && value.value === name;
}

/** True when a value tree reads list `name` through any reporter. */
export function valueUsesList(value: ValueNode, name: string): boolean {
  if (value.kind !== 'Op' && value.kind !== 'Call') return false;
  if (value.kind === 'Op') {
    const nameIndex = LIST_NAME_ARG_INDEX[value.op];
    if (nameIndex !== undefined && textArgumentIs(value.args[nameIndex], name)) return true;
  }
  return value.args.some(arg => valueUsesList(arg, name)) || valueUsesList(value.saved, name);
}
