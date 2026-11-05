<script setup lang="ts">
import type { StrandLike } from './host';
import type { BlockNode } from '../graph/blockGraph';
import InstructionList from './InstructionList.vue';

defineProps<{ strand: StrandLike<BlockNode> }>();
</script>

<template>
  <div class="strand-card" :data-strand-id="strand.id">
    <InstructionList :strand-id="strand.id" :base-path="[]" :instructions="strand.instructions" />
  </div>
</template>
