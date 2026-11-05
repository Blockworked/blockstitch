<script setup lang="ts">
// Generic right-click menu chrome — positioning, outside-click/Escape/scroll
// close, and item rendering. The host owns *what* the menu shows: it builds
// an `items` list (whatever it wants — block actions, canvas actions, a
// variable's actions, ...) and this component just presents it.
import { nextTick, onBeforeUnmount, ref, watch, type Component } from 'vue';

export interface ContextMenuItem {
  key: string;
  label: string;
  icon?: Component;
  onSelect(): void;
  danger?: boolean;
  active?: boolean;
  disabled?: boolean;
  /** Extra class for one-off per-item styling (e.g. a two-click confirm's
   * "armed" state). */
  extraClass?: string;
}

const props = defineProps<{ open: boolean; x: number; y: number; items: ContextMenuItem[] }>();
const emit = defineEmits<{ close: [] }>();

const panelRef = ref<HTMLDivElement | null>(null);
const panelStyle = ref<{ left: string; top: string }>({ left: '0px', top: '0px' });

function positionPanel() {
  const panel = panelRef.value;
  if (!panel) return;
  const left = Math.max(4, Math.min(props.x, window.innerWidth - panel.offsetWidth - 4));
  const top = Math.max(4, Math.min(props.y, window.innerHeight - panel.offsetHeight - 4));
  panelStyle.value = { left: `${left}px`, top: `${top}px` };
}

function close() {
  emit('close');
}

function onOutsideMouseDown(e: MouseEvent) {
  if (panelRef.value?.contains(e.target as Node)) return;
  close();
}
function onKeydown(e: KeyboardEvent) {
  if (e.key === 'Escape') close();
}
function onScrollOrResize() {
  close();
}

watch(
  () => props.open,
  async open => {
    if (open) {
      await nextTick();
      positionPanel();
      document.addEventListener('mousedown', onOutsideMouseDown, true);
      document.addEventListener('keydown', onKeydown);
      window.addEventListener('scroll', onScrollOrResize, true);
      window.addEventListener('resize', onScrollOrResize);
    } else {
      document.removeEventListener('mousedown', onOutsideMouseDown, true);
      document.removeEventListener('keydown', onKeydown);
      window.removeEventListener('scroll', onScrollOrResize, true);
      window.removeEventListener('resize', onScrollOrResize);
    }
  },
);

onBeforeUnmount(() => close());

function onItemClick(item: ContextMenuItem) {
  if (item.disabled) return;
  item.onSelect();
}
</script>

<template>
  <Teleport to="#dd-portal">
    <div v-if="open" ref="panelRef" class="context-menu" role="menu" :style="panelStyle">
      <button
        v-for="item in items"
        :key="item.key"
        type="button"
        class="context-menu-item"
        :class="[{ 'context-menu-item-danger': item.danger, 'context-menu-item-active': item.active }, item.extraClass]"
        role="menuitem"
        :disabled="item.disabled"
        @click="onItemClick(item)"
      >
        <span v-if="item.icon" class="context-menu-item-icon"><component :is="item.icon" /></span>
        <span>{{ item.label }}</span>
      </button>
    </div>
  </Teleport>
</template>
