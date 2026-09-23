<!-- Sidebar launcher for a document's dicts: one checkable row per dict
  that toggles its canvas monitor. Data comes from the `dicts` prop; open
  state lives in `./dictEditors` (persisted via the host's configured save).
  Right-click handling stays host-specific, surfaced as `menu`. -->
<script setup lang="ts">
import { computed } from 'vue';
import { Check } from 'lucide-vue-next';
import { isDictEditorOpen, setDictEditorOpen } from './dictEditors';
import type { DictDef } from './dictTypes';

const props = defineProps<{ dicts: readonly DictDef[] }>();
const emit = defineEmits<{ menu: [name: string, event: MouseEvent] }>();

// Presentation order only — dict data itself stays in its persisted order so
// sorting the sidebar never changes a document or an open editor.
const sorted = computed(() => [...props.dicts]
  .sort((left, right) => left.name.localeCompare(right.name, undefined, { sensitivity: 'base' })));

function toggle(name: string) {
  setDictEditorOpen(name, !isDictEditorOpen(name));
}
</script>

<template>
  <div class="dict-launcher">
    <p v-if="!sorted.length" class="dict-launcher-empty">Make a dict, then check it to open its editor on the canvas.</p>
    <div v-for="dict in sorted" :key="dict.name" class="dict-launcher-row" @contextmenu="emit('menu', dict.name, $event)">
      <button
        type="button"
        class="dict-visibility-toggle"
        :class="{ active: isDictEditorOpen(dict.name) }"
        role="checkbox"
        :aria-checked="isDictEditorOpen(dict.name)"
        :aria-label="`Show ${dict.name} on canvas`"
        @click="toggle(dict.name)"
      >
        <Check v-if="isDictEditorOpen(dict.name)" :size="12" :stroke-width="3" />
      </button>
      <span class="dict-launcher-name">{{ dict.name }}</span>
      <span class="dict-launcher-count">{{ dict.entries.length }}</span>
    </div>
  </div>
</template>

<style scoped>
.dict-launcher{padding:0 var(--blockstitch-spacing-sm) var(--blockstitch-spacing-sm);display:flex;flex-direction:column;gap:3px}.dict-launcher-row{min-height:27px;display:flex;align-items:center;gap:7px;padding:4px 6px;border-radius:var(--blockstitch-radius);color:var(--blockstitch-text)}.dict-launcher-row:hover{background:var(--blockstitch-hover-overlay)}.dict-visibility-toggle{width:18px;min-width:18px;height:18px;min-height:18px;padding:0;display:grid;place-items:center;border:1px solid var(--blockstitch-border);border-radius:4px;background:var(--blockstitch-bg);color:var(--blockstitch-text);box-shadow:var(--blockstitch-bevel-top);cursor:pointer}.dict-visibility-toggle:hover{border-color:var(--blockstitch-accent);background:var(--blockstitch-hover-overlay)}.dict-visibility-toggle.active{background:var(--blockstitch-accent);border-color:var(--blockstitch-accent);color:#fff;box-shadow:inset 0 1px 0 rgba(255,255,255,.2)}.dict-visibility-toggle:focus-visible{outline:2px solid var(--blockstitch-accent);outline-offset:2px}.dict-launcher-name{overflow:hidden;text-overflow:ellipsis;white-space:nowrap;font-size:12px}.dict-launcher-count{margin-left:auto;color:var(--blockstitch-text-dim);font-size:11px}.dict-launcher-empty{padding:4px 0;color:var(--blockstitch-text-dim);font-size:12px;line-height:1.35}
</style>
