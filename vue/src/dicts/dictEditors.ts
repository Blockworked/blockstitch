// Client-side positions for a document's visible dict monitors. Their
// source of truth is persisted on each dict; this reactive copy keeps drag
// feedback immediate while the save completes. The host injects its own
// persistence (a backend command) via `configureDictEditorPersistence` —
// this module never talks to a backend itself.
import { reactive } from 'vue';
import type { DictDef } from './dictTypes';

export interface DictEditorPosition {
  x: number;
  y: number;
}

type PersistDictEditorState = (name: string, visible: boolean, x: number, y: number) => void;

let persist: PersistDictEditorState = () => {};
let activeDocumentId: string | null = null;

export function configureDictEditorPersistence(save: PersistDictEditorState): void {
  persist = save;
}

export const dictEditors = reactive<Record<string, DictEditorPosition>>({});

function normalizedPosition(position: DictEditorPosition): DictEditorPosition {
  return { x: Math.max(0, Math.round(position.x)), y: Math.max(0, Math.round(position.y)) };
}

/** Hydrate visible editors whenever a different document becomes selected. */
export function activateDictEditors(documentId: string | null, dicts: readonly DictDef[]): void {
  if (documentId === activeDocumentId) return;
  activeDocumentId = documentId;
  for (const name of Object.keys(dictEditors)) delete dictEditors[name];
  for (const dict of dicts) {
    if (!dict.editor_visible) continue;
    dictEditors[dict.name] = normalizedPosition({ x: dict.editor_x, y: dict.editor_y });
  }
}

export function isDictEditorOpen(name: string): boolean {
  return name in dictEditors;
}

export function setDictEditorOpen(name: string, open: boolean): void {
  const position =
    dictEditors[name] ?? {
      x: 36 + Object.keys(dictEditors).length * 24,
      y: 36 + Object.keys(dictEditors).length * 24,
    };
  const normalized = normalizedPosition(position);
  if (open) dictEditors[name] = normalized;
  else delete dictEditors[name];
  persist(name, open, normalized.x, normalized.y);
}

/** Removes an editor locally when its dict itself has been deleted. */
export function forgetDictEditor(name: string): void {
  delete dictEditors[name];
}

/** Commit the most recent drag position without changing visibility. */
export function saveDictEditorPosition(name: string): void {
  const position = dictEditors[name];
  if (!position) return;
  const normalized = normalizedPosition(position);
  dictEditors[name] = normalized;
  persist(name, true, normalized.x, normalized.y);
}

export function renameDictEditor(oldName: string, newName: string): void {
  const position = dictEditors[oldName];
  if (!position) return;
  delete dictEditors[oldName];
  dictEditors[newName] = position;
}
