// List data model shared by every blockstitch host: a named,
// document-scoped ordered collection of literal number/text items.
// Mirrors blockstitch-core's `graph::lists::{ListDef, ListItem}` on the
// wire (`{kind:'Number'|'Text', value}` items, `editor_*` canvas state).
export type ListItem = { kind: 'Number'; value: number } | { kind: 'Text'; value: string };

export interface ListDef {
  name: string;
  items: ListItem[];
  editor_visible: boolean;
  editor_x: number;
  editor_y: number;
}

/** Declared list names in sorted order — for sidebar/dropdown display. */
export function sortedListNames(lists: readonly ListDef[] | null | undefined): string[] {
  return [...(lists ?? [])].map(list => list.name).sort((a, b) => a.localeCompare(b));
}

/** Coerces a monitor edit to a literal item: finite numbers stay numeric. */
export function listItemFromText(text: string): ListItem {
  const number = Number(text);
  return text.trim() !== '' && Number.isFinite(number)
    ? { kind: 'Number', value: number }
    : { kind: 'Text', value: text };
}
