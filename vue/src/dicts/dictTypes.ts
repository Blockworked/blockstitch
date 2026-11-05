// Dict data model shared by every blockstitch host: a named,
// document-scoped string-keyed collection of literal number/text values.
// Mirrors blockstitch-core's `graph::dicts::{DictDef, DictEntry, DictItem}`
// on the wire (`{key, value: {kind:'Number'|'Text', value}}` entries,
// `editor_*` canvas state).
export type DictItem = { kind: 'Number'; value: number } | { kind: 'Text'; value: string };

export interface DictEntry {
  key: string;
  value: DictItem;
}

export interface DictDef {
  name: string;
  entries: DictEntry[];
  editor_visible: boolean;
  editor_x: number;
  editor_y: number;
}

/** Declared dict names in sorted order — for sidebar/dropdown display. */
export function sortedDictNames(dicts: readonly DictDef[] | null | undefined): string[] {
  return [...(dicts ?? [])].map(dict => dict.name).sort((a, b) => a.localeCompare(b));
}

/** Coerces a monitor edit to a literal item: finite numbers stay numeric. */
export function dictItemFromText(text: string): DictItem {
  const number = Number(text);
  return text.trim() !== '' && Number.isFinite(number)
    ? { kind: 'Number', value: number }
    : { kind: 'Text', value: text };
}
