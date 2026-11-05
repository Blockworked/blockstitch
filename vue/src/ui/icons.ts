// Runtime icon registry backing AppButton/AppDropdown/CommentCard etc. — a
// small built-in set covers blockstitch's own chrome; the host registers its
// full icon set (including one per block type) at startup via
// `registerIcons`, so every `icon="..."` string used anywhere in the host
// app resolves the same way it always has.
import type { Component } from 'vue';
import { ChevronUp, ChevronDown, X, MessageSquare } from '@lucide/vue';

export type IconName = string;

const registry: Record<string, Component> = {
  'chevron-up': ChevronUp,
  'chevron-down': ChevronDown,
  x: X,
  'message-square': MessageSquare,
};

export function registerIcon(name: string, component: Component): void {
  registry[name] = component;
}

export function registerIcons(map: Record<string, Component>): void {
  Object.assign(registry, map);
}

export function getIcon(name: string): Component | undefined {
  return registry[name];
}
