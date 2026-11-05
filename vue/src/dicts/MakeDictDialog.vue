<!-- "Make a Dict" / "Rename Dict" dialog. Creating and renaming go through
  the host's `onSubmit`, which rejects (throws) on a validation error shown
  inline; success closes the dialog via `close`. -->
<script setup lang="ts">
import { computed, nextTick, ref, watch } from 'vue';
import { renameDictEditor } from './dictEditors';

const props = defineProps<{
  renameTarget?: string | null;
  onSubmit: (name: string, renameTarget: string | null | undefined) => Promise<void>;
}>();
const emit = defineEmits<{ close: [] }>();
const isRename = computed(() => !!props.renameTarget);
const name = ref(props.renameTarget ?? '');
const error = ref<string | null>(null);
const submitting = ref(false);
const inputEl = ref<HTMLInputElement | null>(null);

watch(inputEl, async el => {
  if (!el) return;
  await nextTick();
  el.focus();
});

async function onOk() {
  if (submitting.value) return;
  submitting.value = true;
  try {
    await props.onSubmit(name.value, props.renameTarget);
    if (props.renameTarget) renameDictEditor(props.renameTarget, name.value);
    emit('close');
  } catch (e) {
    error.value = String(e);
  } finally {
    submitting.value = false;
  }
}
</script>

<template>
  <Teleport to="body">
    <div class="modal-overlay" @pointerdown.self="emit('close')">
      <div class="modal-panel">
        <h2 class="modal-title">{{ isRename ? 'Rename Dict' : 'Make a Dict' }}</h2>
        <input
          ref="inputEl"
          v-model="name"
          type="text"
          class="modal-input"
          :class="{ invalid: error }"
          placeholder="Dict name"
          @keydown.enter="onOk"
          @keydown.esc="emit('close')"
        >
        <span v-if="error" class="invalid-hint">{{ error }}</span>
        <div class="modal-actions">
          <button type="button" @click="emit('close')">Cancel</button>
          <button type="button" class="btn-primary" :disabled="submitting" @click="onOk">OK</button>
        </div>
      </div>
    </div>
  </Teleport>
</template>
