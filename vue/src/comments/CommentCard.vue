<script setup lang="ts">
import { nextTick, onMounted, ref, watch } from 'vue';
import type { CommentLike } from '../canvas/host';
import { getHost } from '../canvas/host';
import { beginCommentDrag } from '../canvas/canvasDrag';
import { consumePendingFocus } from './commentFocus';
import { getIcon } from '../ui/icons';

const props = defineProps<{ comment: CommentLike }>();

const textareaEl = ref<HTMLTextAreaElement | null>(null);

function resize() {
  const el = textareaEl.value;
  if (!el) return;
  el.style.height = 'auto';
  el.style.height = `${el.scrollHeight}px`;
}

watch(() => props.comment.text, () => nextTick(resize));
watch(() => props.comment.collapsed, collapsed => { if (!collapsed) nextTick(resize); });

onMounted(() => {
  resize();
  if (consumePendingFocus(props.comment.id)) {
    nextTick(() => textareaEl.value?.focus());
  }
});

// Only the title bar starts a drag — a click on either button must not.
function onHeaderPointerDown(e: PointerEvent) {
  if ((e.target as Element | null)?.closest?.('button')) return;
  beginCommentDrag(e, props.comment.id);
}

function onToggleCollapsed() {
  void getHost().backend.setCommentCollapsed?.(props.comment.id, !props.comment.collapsed);
}

function onDelete() {
  void getHost().backend.removeComment?.(props.comment.id);
}

function onTextInput(e: Event) {
  void getHost().backend.editCommentText?.(props.comment.id, (e.target as HTMLTextAreaElement).value);
}
</script>

<template>
  <div
    class="comment-card"
    :class="{ 'comment-card-collapsed': comment.collapsed, 'comment-card-attached': comment.attached_to != null }"
    :data-comment-id="comment.id"
  >
    <div class="comment-card-header" @pointerdown="onHeaderPointerDown">
      <component :is="getIcon('message-square')" class="comment-card-icon" />
      <span class="comment-card-title">Comment</span>
      <button type="button" class="comment-card-btn" :title="comment.collapsed ? 'Expand' : 'Collapse'" @click="onToggleCollapsed">
        <component :is="getIcon(comment.collapsed ? 'chevron-down' : 'chevron-up')" />
      </button>
      <button type="button" class="comment-card-btn comment-card-delete" title="Delete comment" @click="onDelete">
        <component :is="getIcon('x')" />
      </button>
    </div>
    <textarea
      v-show="!comment.collapsed"
      ref="textareaEl"
      class="comment-card-body"
      placeholder="Comment"
      rows="1"
      :value="comment.text"
      @input="onTextInput"
    />
  </div>
</template>
