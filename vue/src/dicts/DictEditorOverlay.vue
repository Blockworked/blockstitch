<!-- Draggable canvas monitor for one dict: its literal entries, editable
  in place. Position/drag state lives in `./dictEditors` (persisted via the
  host's configured save); entry and name changes go through the host's
  `onSaveEntries`/`onRename` callbacks. Hiding goes through `onHide`, which
  must close the editor (e.g. via `setDictEditorOpen(name, false)`). -->
<script setup lang="ts">
import { computed, nextTick, ref, watch } from 'vue';
import { Check, GripVertical, Pencil, Plus, X } from '@lucide/vue';
import { dictEditors, renameDictEditor, saveDictEditorPosition } from './dictEditors';
import { dictItemFromText, type DictDef, type DictEntry } from './dictTypes';

const props = defineProps<{
  dict: DictDef;
  onSaveEntries: (name: string, entries: DictEntry[]) => void;
  onRename: (oldName: string, newName: string) => Promise<void>;
  onHide: (name: string) => void;
}>();

const position = computed(() => dictEditors[props.dict.name] ?? { x: 36, y: 36 });
const editingName = ref(false);
const nameDraft = ref('');
const error = ref<string | null>(null);
const pendingFocusIndex = ref<number | null>(null);
const valueInputs = new Map<number, HTMLInputElement>();
let drag: { pointerId: number; clientX: number; clientY: number; x: number; y: number } | null = null;

function captureValueInput(index: number, element: unknown) {
  if (element instanceof HTMLInputElement) valueInputs.set(index, element);
  else valueInputs.delete(index);
}

watch(
  () => props.dict.entries.length,
  async length => {
    const index = pendingFocusIndex.value;
    if (index === null || length === undefined || length <= index) return;
    await nextTick();
    const input = valueInputs.get(index);
    input?.focus();
    input?.select();
    pendingFocusIndex.value = null;
  },
);

function editKey(index: number, key: string) {
  const entries = [...props.dict.entries];
  entries[index] = { key, value: entries[index].value };
  props.onSaveEntries(props.dict.name, entries);
}

function editValue(index: number, text: string) {
  const entries = [...props.dict.entries];
  entries[index] = { key: entries[index].key, value: dictItemFromText(text) };
  props.onSaveEntries(props.dict.name, entries);
}

function addEntry() {
  pendingFocusIndex.value = props.dict.entries.length;
  props.onSaveEntries(props.dict.name, [...props.dict.entries, { key: '', value: { kind: 'Text', value: '' } }]);
}

function addEntryBelow(index: number, text: string) {
  const entries = [...props.dict.entries];
  entries[index] = { key: entries[index].key, value: dictItemFromText(text) };
  const nextIndex = index + 1;
  entries.splice(nextIndex, 0, { key: '', value: { kind: 'Text', value: '' } });
  pendingFocusIndex.value = nextIndex;
  props.onSaveEntries(props.dict.name, entries);
}

function removeEntry(index: number) {
  props.onSaveEntries(props.dict.name, props.dict.entries.filter((_, entryIndex) => entryIndex !== index));
}

async function rename() {
  try {
    const nextName = nameDraft.value.trim();
    await props.onRename(props.dict.name, nextName);
    renameDictEditor(props.dict.name, nextName);
    editingName.value = false;
    error.value = null;
  } catch (e) {
    error.value = String(e);
  }
}

function startDrag(event: PointerEvent) {
  if ((event.target as Element).closest('button, input')) return;
  const editor = dictEditors[props.dict.name];
  if (!editor) return;
  event.preventDefault();
  event.stopPropagation();
  (event.currentTarget as HTMLElement).setPointerCapture(event.pointerId);
  drag = { pointerId: event.pointerId, clientX: event.clientX, clientY: event.clientY, x: editor.x, y: editor.y };
}

function moveDrag(event: PointerEvent) {
  if (!drag || drag.pointerId !== event.pointerId) return;
  const editor = dictEditors[props.dict.name];
  if (!editor) return;
  editor.x = Math.max(0, drag.x + event.clientX - drag.clientX);
  editor.y = Math.max(0, drag.y + event.clientY - drag.clientY);
}

function endDrag(event: PointerEvent) {
  if (drag?.pointerId === event.pointerId) {
    drag = null;
    saveDictEditorPosition(props.dict.name);
  }
}
</script>

<template>
  <aside
    class="dict-canvas-editor"
    :style="{ left: `${position.x}px`, top: `${position.y}px` }"
  >
    <header class="dict-canvas-editor-header" @pointerdown="startDrag" @pointermove="moveDrag" @pointerup="endDrag" @pointercancel="endDrag">
      <GripVertical :size="16" class="dict-grip" />
      <template v-if="editingName">
        <input v-model="nameDraft" @keydown.enter.prevent="rename" @keydown.esc="editingName = false">
        <button type="button" title="Save name" @click="rename"><Check :size="15" /></button>
      </template>
      <template v-else>
        <strong>{{ dict.name }}</strong>
        <button type="button" title="Rename dict" @click="nameDraft = dict.name; editingName = true"><Pencil :size="14" /></button>
      </template>
      <button type="button" title="Hide editor" @click="onHide(dict.name)"><X :size="15" /></button>
    </header>
    <div class="dict-canvas-editor-items">
      <div v-if="!dict.entries.length" class="dict-canvas-editor-empty">This dict is empty.</div>
      <div v-for="(entry, index) in dict.entries" :key="index" class="dict-canvas-editor-row">
        <input
          :value="entry.key"
          class="is-key"
          placeholder="key"
          @change="editKey(index, ($event.target as HTMLInputElement).value)"
        >
        <input
          :ref="element => captureValueInput(index, element)"
          :value="String(entry.value.value)"
          :class="entry.value.kind === 'Number' ? 'is-number' : 'is-text'"
          @change="editValue(index, ($event.target as HTMLInputElement).value)"
          @keydown.enter.prevent="addEntryBelow(index, ($event.target as HTMLInputElement).value)"
        >
        <button type="button" title="Remove entry" @click="removeEntry(index)"><X :size="15" /></button>
      </div>
    </div>
    <button type="button" class="dict-canvas-add" @click="addEntry"><Plus :size="15" /> Add entry</button>
    <footer>{{ dict.entries.length }} {{ dict.entries.length === 1 ? 'entry' : 'entries' }}</footer>
    <p v-if="error" class="dict-canvas-error">{{ error }}</p>
  </aside>
</template>

<style scoped>
.dict-canvas-editor{position:absolute;z-index:12;width:340px;max-height:400px;display:flex;flex-direction:column;border:1px solid var(--blockstitch-border);border-radius:8px;background:var(--blockstitch-bg2);color:var(--blockstitch-text);box-shadow:var(--blockstitch-shadow-lg);overflow:hidden;pointer-events:auto}.dict-canvas-editor-header{min-height:36px;display:flex;align-items:center;gap:4px;padding:5px 6px;border-bottom:1px solid var(--blockstitch-glass-border);background:var(--blockstitch-glass-bg-strong);cursor:grab;touch-action:none}.dict-canvas-editor-header:active{cursor:grabbing}.dict-grip{color:var(--blockstitch-text-dim);flex-shrink:0}.dict-canvas-editor-header strong{flex:1;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;font-size:13px}.dict-canvas-editor-header input{min-width:0;flex:1;border:1px solid var(--blockstitch-border);border-radius:4px;background:var(--blockstitch-bg2);color:var(--blockstitch-text);padding:4px 5px;font:inherit;font-size:12px}.dict-canvas-editor button{min-height:unset;padding:4px;border:0;background:transparent;color:var(--blockstitch-text-dim);border-radius:4px}.dict-canvas-editor button:hover{background:var(--blockstitch-hover-overlay);color:var(--blockstitch-text)}.dict-canvas-editor button.danger:hover,.dict-canvas-editor-row button:hover{color:var(--blockstitch-red);background:rgba(var(--blockstitch-red-rgb),.12)}.dict-canvas-editor-items{max-height:250px;overflow:auto;padding:6px}.dict-canvas-editor-row{display:grid;grid-template-columns:1fr 1fr 24px;align-items:center;gap:4px;padding:2px}.dict-canvas-editor-row input{min-width:0;border:1px solid var(--blockstitch-border);border-radius:5px;background:var(--blockstitch-bg);color:var(--blockstitch-text);padding:5px 6px;font:inherit;font-size:12px}.dict-canvas-editor-row input.is-number{color:var(--blockstitch-accent-light)}.dict-canvas-editor-row input.is-key{font-weight:700}.dict-canvas-editor-empty{padding:8px 4px;color:var(--blockstitch-text-dim);font-size:12px}.dict-canvas-add{margin:0 6px 6px;border:1px dashed var(--blockstitch-border)!important;width:calc(100% - 12px);display:flex!important;justify-content:center;gap:4px;color:var(--blockstitch-text-dim)!important;font-size:12px;font-weight:700}.dict-canvas-add:hover{color:var(--blockstitch-accent-light)!important;border-color:var(--blockstitch-accent)!important}.dict-canvas-editor footer{border-top:1px solid var(--blockstitch-glass-border);padding:6px 8px;color:var(--blockstitch-text-dim);font-size:11px;font-weight:700}.dict-canvas-editor footer span{float:right;font-weight:400}.dict-canvas-error{padding:0 8px 6px;color:var(--blockstitch-red);font-size:11px}
.dict-canvas-editor-items{scrollbar-width:thin;scrollbar-color:var(--blockstitch-scrollbar-thumb) transparent}.dict-canvas-editor-items::-webkit-scrollbar{width:10px}.dict-canvas-editor-items::-webkit-scrollbar-track{background:transparent}.dict-canvas-editor-items::-webkit-scrollbar-thumb{background:var(--blockstitch-scrollbar-thumb);border:2px solid transparent;border-radius:8px;background-clip:padding-box}.dict-canvas-editor-items::-webkit-scrollbar-thumb:hover{background:var(--blockstitch-scrollbar-thumb-hover);background-clip:padding-box}.dict-canvas-editor-items::-webkit-scrollbar-button{display:none;width:0;height:0}
</style>
