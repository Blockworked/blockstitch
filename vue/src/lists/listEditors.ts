// Client-side positions for a document's visible list monitors. Their
// source of truth is persisted on each list; this reactive copy keeps drag
// feedback immediate while the save completes. The host injects its own
// persistence (a backend command) via `configureListEditorPersistence` —
// this module never talks to a backend itself.
import { reactive } from 'vue';
import type { ListDef } from './listTypes';

export interface ListEditorPosition {
  x: number;
  y: number;
}

type PersistListEditorState = (name: string, visible: boolean, x: number, y: number) => void;

let persist: PersistListEditorState = () => {};
let activeDocumentId: string | null = null;

export function configureListEditorPersistence(save: PersistListEditorState): void {
  persist = save;
}

export const listEditors = reactive<Record<string, ListEditorPosition>>({});

function normalizedPosition(position: ListEditorPosition): ListEditorPosition {
  return { x: Math.max(0, Math.round(position.x)), y: Math.max(0, Math.round(position.y)) };
}

/** Hydrate visible editors whenever a different document becomes selected. */
export function activateListEditors(documentId: string | null, lists: readonly ListDef[]): void {
  if (documentId === activeDocumentId) return;
  activeDocumentId = documentId;
  for (const name of Object.keys(listEditors)) delete listEditors[name];
  for (const list of lists) {
    if (!list.editor_visible) continue;
    listEditors[list.name] = normalizedPosition({ x: list.editor_x, y: list.editor_y });
  }
}

export function isListEditorOpen(name: string): boolean {
  return name in listEditors;
}

export function setListEditorOpen(name: string, open: boolean): void {
  const position =
    listEditors[name] ?? {
      x: 36 + Object.keys(listEditors).length * 24,
      y: 36 + Object.keys(listEditors).length * 24,
    };
  const normalized = normalizedPosition(position);
  if (open) listEditors[name] = normalized;
  else delete listEditors[name];
  persist(name, open, normalized.x, normalized.y);
}

/** Removes an editor locally when its list itself has been deleted. */
export function forgetListEditor(name: string): void {
  delete listEditors[name];
}

/** Commit the most recent drag position without changing visibility. */
export function saveListEditorPosition(name: string): void {
  const position = listEditors[name];
  if (!position) return;
  const normalized = normalizedPosition(position);
  listEditors[name] = normalized;
  persist(name, true, normalized.x, normalized.y);
}

export function renameListEditor(oldName: string, newName: string): void {
  const position = listEditors[oldName];
  if (!position) return;
  delete listEditors[oldName];
  listEditors[newName] = position;
}
