// blockstitch — a generic, Scratch-style draggable block-editor library for
// Vue 3. The host app supplies its own block vocabulary (instruction types,
// operators, field forms, icons) via the registries below, and its own
// backend via `configureCanvas`; this package owns the canvas/pan/zoom,
// drag/snap, value-expression, palette, comment, and theming machinery.
// Import `blockstitch/theme.css` once, globally, alongside this module.

// ── Block graph (generic instruction-tree addressing) ──────────────────────
export * from './graph/blockGraph';
export * from './graph/shapeRegistry';
export * from './graph/fieldRegistry';
export * from './graph/operatorRegistry';

// ── Lists (document-scoped literal collections + monitors) ────────────────
export * from './lists/listTypes';
export * from './lists/listOperators';
export * from './lists/listNames';
export * from './lists/listEditors';
export * from './lists/listDialogs';
export { default as ListPanel } from './lists/ListPanel.vue';
export { default as ListEditorOverlay } from './lists/ListEditorOverlay.vue';
export { default as MakeListDialog } from './lists/MakeListDialog.vue';

// ── Canvas host wiring ──────────────────────────────────────────────────────
export * from './canvas/host';
export {
  attachDragListeners,
  beginCommentDrag,
  beginPaletteDrag,
  beginPickup,
  capturePointer,
  clientToCanvas,
  getCanvasZoom,
  isOverSidebar,
  positionCanvas,
  resetCanvasView,
  setSidebarArmed,
  zoomInCanvas,
  zoomOutCanvas,
} from './canvas/canvasDrag';

// ── Canvas components ────────────────────────────────────────────────────────
export { default as Canvas } from './canvas/Canvas.vue';
export { default as StrandCard } from './canvas/StrandCard.vue';
export { default as InstructionList } from './canvas/InstructionList.vue';
export { default as InstructionRow } from './canvas/InstructionRow.vue';
export { default as PaletteInstructionBlock } from './canvas/PaletteInstructionBlock.vue';
export { default as PaletteValueBlock } from './canvas/PaletteValueBlock.vue';
export { default as PaletteNumberField } from './canvas/PaletteNumberField.vue';

// ── Values ───────────────────────────────────────────────────────────────────
export * from './values/valueNode';
export {
  attachValueDragListeners,
  beginValuePaletteDrag,
  beginValuePickup,
  capsuleLocations,
  dragReveal,
  evalPreview,
  isCapsuleLocation,
  paletteEvalPreview,
} from './values/valueDrag';
export { default as ValueBlock } from './values/ValueBlock.vue';
export { default as FloatingValueCard } from './values/FloatingValueCard.vue';

// ── Comments ─────────────────────────────────────────────────────────────────
export * from './comments/commentFocus';
export { default as CommentCard } from './comments/CommentCard.vue';

// ── UI primitives ────────────────────────────────────────────────────────────
export * from './ui/icons';
export * from './ui/dropdownRegistry';
export { default as AppDropdown } from './ui/AppDropdown.vue';
export { default as AppButton } from './ui/AppButton.vue';
export { default as AutosizeInput } from './ui/AutosizeInput.vue';
export { default as SwitchControl } from './ui/SwitchControl.vue';
export { default as ContextMenuPanel, type ContextMenuItem } from './ui/ContextMenuPanel.vue';

// ── Theming ──────────────────────────────────────────────────────────────────
export * from './theme/useTheme';

// ── Composables ──────────────────────────────────────────────────────────────
export * from './composables/useSidebarWidth';
