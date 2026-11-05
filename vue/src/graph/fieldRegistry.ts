// Which Vue component renders a block type's own fields — the host registers
// one entry per instruction type it defines, at startup. For a wrap-shaped
// type (see shapeRegistry.ts), the same component is rendered twice, with a
// `part: 'head' | 'body'` prop, exactly like an ordinary type is rendered
// once with no `part` prop — the component itself decides what each part
// looks like.
import type { Component } from 'vue';

const fieldComponents = new Map<string, Component>();
const paletteFieldComponents = new Map<string, Component>();

/** Registers the real-canvas-row field component for `type`. */
export function registerBlockField(type: string, component: Component): void {
  fieldComponents.set(type, component);
}

export function getBlockField(type: string): Component | undefined {
  return fieldComponents.get(type);
}

/** Registers the sidebar-prefab field component for `type` — usually a
 * lighter variant of the real-row component (editable, but never a drag
 * source/drop target for nested values). Falls back to the real-row
 * component (`getBlockField`) if no palette-specific one was registered. */
export function registerPaletteBlockField(type: string, component: Component): void {
  paletteFieldComponents.set(type, component);
}

export function getPaletteBlockField(type: string): Component | undefined {
  return paletteFieldComponents.get(type) ?? fieldComponents.get(type);
}
