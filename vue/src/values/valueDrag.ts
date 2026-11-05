// Pointer-drag state machine for value blocks (numbers, text, operators,
// variables, ...). Kept separate from canvas/canvasDrag.ts's strand
// drag/snap machinery so a value block structurally can't attach to a
// strand's instruction list (this file never touches instruction/strand
// backend calls, only the value-shaped ones).
import { ref } from 'vue';
import { capturePointer, clientToCanvas, getCanvasZoom, isOverSidebar, setSidebarArmed } from '../canvas/canvasDrag';
import { getHost, isLocked } from '../canvas/host';
import { locationsEqual } from '../graph/blockGraph';
import type { ValueLocation } from '../graph/blockGraph';
import { isPreviewableKind, isPreviewableValue, savedOf, type ValueNode } from './valueNode';

/** Field/subfield locations whose current leaf (a plain literal) got there by
 * being dropped in (not just typed) — ValueBlock.vue's `boxed` consults this
 * so a dropped-in leaf keeps its capsule look and stays pickup-draggable.
 * Frontend-only affordance, not persisted; doesn't survive reload or
 * undo/redo. */
export const capsuleLocations = ref<ValueLocation[]>([]);

export function isCapsuleLocation(location: ValueLocation): boolean {
  return capsuleLocations.value.some(l => locationsEqual(l, location));
}

function markOrUnmark(location: ValueLocation, value: ValueNode) {
  const isLeaf = value.kind === 'Number' || value.kind === 'Text';
  const already = isCapsuleLocation(location);
  if (isLeaf && !already) capsuleLocations.value.push(location);
  else if (!isLeaf && already) capsuleLocations.value = capsuleLocations.value.filter(l => !locationsEqual(l, location));
}

function unmarkCapsule(location: ValueLocation) {
  if (isCapsuleLocation(location)) capsuleLocations.value = capsuleLocations.value.filter(l => !locationsEqual(l, location));
}

// While a field/subfield value is mid-drag, its origin ValueBlock renders
// this instead of its real prop — the value take_value would leave behind —
// so the slot reads correctly immediately instead of sitting blank until the
// async take/put round trip lands.
export const dragReveal = ref<{ location: ValueLocation; value: ValueNode } | null>(null);

const EVAL_PREVIEW_TIMEOUT_MS = 2500;

// A click (pointerdown+up without crossing the drag threshold) on an
// operator block samples-evaluates it and shows the result here;
// ValueBlock.vue renders a tooltip beside the matching location.
// Auto-dismisses after a timeout.
export const evalPreview = ref<{ location: ValueLocation; text: string; error: boolean } | null>(null);
let evalPreviewTimer: ReturnType<typeof setTimeout> | null = null;

function showEvalPreview(location: ValueLocation, text: string, error: boolean) {
  if (evalPreviewTimer) clearTimeout(evalPreviewTimer);
  evalPreview.value = { location, text, error };
  evalPreviewTimer = setTimeout(() => {
    evalPreview.value = null;
    evalPreviewTimer = null;
  }, EVAL_PREVIEW_TIMEOUT_MS);
}

function clearEvalPreview() {
  if (evalPreviewTimer) {
    clearTimeout(evalPreviewTimer);
    evalPreviewTimer = null;
  }
  evalPreview.value = null;
}

async function previewClickedOperator(location: ValueLocation, value: ValueNode) {
  try {
    const text = await getHost().backend.previewValue(value);
    showEvalPreview(location, text, false);
  } catch (err) {
    showEvalPreview(location, String(err), true);
  }
}

// Same idea as `evalPreview`, but for a sidebar prefab — keyed by `kind`
// since it has no `ValueLocation` yet. PaletteValueBlock.vue renders it.
export const paletteEvalPreview = ref<{ kind: string; text: string; error: boolean } | null>(null);
let paletteEvalPreviewTimer: ReturnType<typeof setTimeout> | null = null;

function showPaletteEvalPreview(kind: string, text: string, error: boolean) {
  if (paletteEvalPreviewTimer) clearTimeout(paletteEvalPreviewTimer);
  paletteEvalPreview.value = { kind, text, error };
  paletteEvalPreviewTimer = setTimeout(() => {
    paletteEvalPreview.value = null;
    paletteEvalPreviewTimer = null;
  }, EVAL_PREVIEW_TIMEOUT_MS);
}

function clearPaletteEvalPreview() {
  if (paletteEvalPreviewTimer) {
    clearTimeout(paletteEvalPreviewTimer);
    paletteEvalPreviewTimer = null;
  }
  paletteEvalPreview.value = null;
}

async function previewClickedPaletteValue(kind: string) {
  try {
    const text = await getHost().backend.previewValue(getHost().resolveFreshValue(kind));
    showPaletteEvalPreview(kind, text, false);
  } catch (err) {
    showPaletteEvalPreview(kind, String(err), true);
  }
}

type ValueDragSource =
  | { kind: 'existing'; location: ValueLocation; value: ValueNode }
  | { kind: 'fresh'; valueKind: string };

interface ValueDragCandidate {
  pointerId: number;
  startX: number;
  startY: number;
  anchorEl: HTMLElement;
  source: ValueDragSource;
}
let valueDragCandidate: ValueDragCandidate | null = null;

interface ValueDragState {
  pointerId: number;
  offsetX: number;
  offsetY: number;
  ghostEl: HTMLElement;
  source: ValueDragSource;
  dropTarget: { el: HTMLElement; location: ValueLocation } | null;
  overTrash: boolean;
  // The real floating-card element, hidden for the drag's duration so it
  // doesn't sit visible next to the ghost tracking the pointer.
  hiddenAnchorEl: HTMLElement | null;
}
let valueDrag: ValueDragState | null = null;

/** Picking up a block that already exists (embedded in a field/subfield, or
 * floating on canvas). `anchorEl` is cloned into the drag ghost once the
 * pointer crosses the click-vs-drag threshold. */
export function beginValuePickup(e: PointerEvent, location: ValueLocation, value: ValueNode, anchorEl: HTMLElement) {
  if (isLocked()) return;
  if (e.button !== undefined && e.button !== 0) return;
  e.preventDefault();
  capturePointer(e);
  clearEvalPreview();
  clearPaletteEvalPreview();
  valueDragCandidate = { pointerId: e.pointerId, startX: e.clientX, startY: e.clientY, anchorEl, source: { kind: 'existing', location, value } };
}

/** Dragging a brand-new block off the sidebar's "Operator" section.
 * `anchorEl` is that kind's hidden ghost template. */
export function beginValuePaletteDrag(e: PointerEvent, valueKind: string, anchorEl: HTMLElement) {
  if (isLocked()) return;
  if (e.button !== undefined && e.button !== 0) return;
  e.preventDefault();
  capturePointer(e);
  clearEvalPreview();
  clearPaletteEvalPreview();
  valueDragCandidate = { pointerId: e.pointerId, startX: e.clientX, startY: e.clientY, anchorEl, source: { kind: 'fresh', valueKind } };
}

let ghostRafPending = false;
let lastPointerEvent: PointerEvent | null = null;
function positionGhost(e: PointerEvent) {
  lastPointerEvent = e;
  if (ghostRafPending) return;
  ghostRafPending = true;
  requestAnimationFrame(() => {
    ghostRafPending = false;
    if (!valueDrag || !lastPointerEvent) return;
    const tx = lastPointerEvent.clientX - valueDrag.offsetX;
    const ty = lastPointerEvent.clientY - valueDrag.offsetY;
    valueDrag.ghostEl.style.transform = `translate(${tx}px, ${ty}px) scale(${getCanvasZoom()})`;
    valueDrag.ghostEl.style.transformOrigin = '0 0';
  });
}

function startValueDrag(e: PointerEvent, candidate: ValueDragCandidate) {
  const rect = candidate.anchorEl.getBoundingClientRect();
  const ghost = document.createElement('div');
  ghost.className = 'value-drag-ghost';
  ghost.appendChild(candidate.anchorEl.cloneNode(true) as HTMLElement);
  document.body.appendChild(ghost);

  // A palette drag's anchorEl is the sidebar's hidden off-screen template, so
  // its rect is off-screen, not cursor-relative — center the ghost under the
  // pointer instead of deriving a click-relative offset from it.
  const isFresh = candidate.source.kind === 'fresh';
  const offsetX = isFresh ? rect.width / 2 : e.clientX - rect.left;
  const offsetY = isFresh ? rect.height / 2 : e.clientY - rect.top;

  let hiddenAnchorEl: HTMLElement | null = null;
  if (candidate.source.kind === 'existing') {
    const { location, value } = candidate.source;
    // A whole floating block has no field to reveal a placeholder in — hide
    // the real card (already cloned into the ghost) instead.
    if (location.kind === 'Floating' && location.path.length === 0) {
      candidate.anchorEl.style.visibility = 'hidden';
      hiddenAnchorEl = candidate.anchorEl;
    } else {
      dragReveal.value = { location, value: savedOf(value) };
    }
  }

  valueDrag = {
    pointerId: candidate.pointerId,
    offsetX,
    offsetY,
    ghostEl: ghost,
    source: candidate.source,
    dropTarget: null,
    overTrash: false,
    hiddenAnchorEl,
  };
  positionGhost(e);
}

/** True only for a location *strictly inside* `root` (one of its own operand
 * slots, at any depth) — never for `root` itself. Dropping back onto the
 * exact slot a value was picked up from is a valid no-op "put it back", not
 * a self-drop; only nesting a value inside its own operand is invalid. */
function isStrictDescendant(candidate: ValueLocation, root: ValueLocation): boolean {
  if (candidate.kind !== root.kind) return false;
  if (candidate.kind === 'Field' && root.kind === 'Field') {
    if (candidate.strand_id !== root.strand_id || candidate.field_id !== root.field_id) return false;
    if (JSON.stringify(candidate.index) !== JSON.stringify(root.index)) return false;
  } else if (candidate.kind === 'Floating' && root.kind === 'Floating') {
    if (candidate.floating_id !== root.floating_id) return false;
  } else {
    return false;
  }
  return candidate.path.length > root.path.length && root.path.every((p, i) => candidate.path[i] === p);
}

function isFloatingRootLocation(location: ValueLocation): boolean {
  return location.kind === 'Floating' && location.path.length === 0;
}

/** Walks up to the nearest `[data-value-location]` block, skipping the
 * dragged block's own subtree (can't drop into itself or its own operand)
 * and a standalone floating card's own root — that's a block placed on
 * purpose in its own right, not a slot waiting to be filled, so dropping
 * onto its background (as opposed to one of its own input fields, which is
 * a nested, more specific match found first) isn't a valid target; the
 * caller's fallback ("no target" → drop as a new floating value) leaves the
 * card it landed on untouched. */
function findDropTarget(clientX: number, clientY: number, exclude: ValueLocation | null): { el: HTMLElement; location: ValueLocation } | null {
  let el: Element | null = document.elementFromPoint(clientX, clientY);
  while (el) {
    const match = el.closest<HTMLElement>('[data-value-location]');
    if (!match) return null;
    let location: ValueLocation;
    try {
      location = JSON.parse(match.dataset.valueLocation ?? '');
    } catch {
      return null;
    }
    const isSelf = !!exclude && isStrictDescendant(location, exclude);
    if (!isSelf && !isFloatingRootLocation(location)) {
      return { el: match, location };
    }
    el = match.parentElement;
  }
  return null;
}

let highlightedEl: HTMLElement | null = null;
function setDropHighlight(target: { el: HTMLElement } | null) {
  const el = target?.el ?? null;
  if (highlightedEl === el) return;
  highlightedEl?.classList.remove('value-drop-target');
  highlightedEl = el;
  highlightedEl?.classList.add('value-drop-target');
}
function clearDropHighlight() {
  setDropHighlight(null);
}

function onPointerMove(e: PointerEvent) {
  if (valueDrag && e.pointerId === valueDrag.pointerId) {
    positionGhost(e);
    if (isOverSidebar(e)) {
      valueDrag.overTrash = true;
      valueDrag.dropTarget = null;
      clearDropHighlight();
      setSidebarArmed(true);
    } else {
      valueDrag.overTrash = false;
      setSidebarArmed(false);
      const exclude = valueDrag.source.kind === 'existing' ? valueDrag.source.location : null;
      const target = findDropTarget(e.clientX, e.clientY, exclude);
      valueDrag.dropTarget = target;
      setDropHighlight(target);
    }
    return;
  }
  if (valueDragCandidate && e.pointerId === valueDragCandidate.pointerId) {
    const dx = e.clientX - valueDragCandidate.startX;
    const dy = e.clientY - valueDragCandidate.startY;
    if (Math.hypot(dx, dy) < 4) return;
    const candidate = valueDragCandidate;
    valueDragCandidate = null;
    startValueDrag(e, candidate);
  }
}

function onPointerUp(e: PointerEvent) {
  if (valueDragCandidate && valueDragCandidate.pointerId === e.pointerId) {
    const candidate = valueDragCandidate;
    valueDragCandidate = null;
    // Never crossed the drag threshold — a plain click. A real pointerup (not
    // a cancel) on an operator/variable block or prefab samples-evaluates it.
    if (e.type === 'pointerup') {
      if (candidate.source.kind === 'existing' && isPreviewableValue(candidate.source.value)) {
        void previewClickedOperator(candidate.source.location, candidate.source.value);
      } else if (candidate.source.kind === 'fresh' && isPreviewableKind(candidate.source.valueKind)) {
        void previewClickedPaletteValue(candidate.source.valueKind);
      }
    }
  }
  if (!valueDrag || valueDrag.pointerId !== e.pointerId) return;

  const finished = valueDrag;
  valueDrag = null;
  clearDropHighlight();
  setSidebarArmed(false);
  finished.ghostEl.remove();

  void (async () => {
    const { backend, resolveFreshValue } = getHost();
    try {
      if (finished.overTrash) {
        if (finished.source.kind === 'existing') {
          const loc = finished.source.location;
          if (loc.kind === 'Floating' && loc.path.length === 0) {
            await backend.removeFloatingValue(loc.floating_id);
          } else {
            await backend.takeValue(loc); // discard — resets the source slot to a default
            unmarkCapsule(loc);
          }
        }
        // Fresh-from-sidebar dropped back on the sidebar: never created, nothing to undo.
        return;
      }
      if (finished.dropTarget) {
        const { location: targetLoc, el: targetEl } = finished.dropTarget;

        // Dropped back onto the exact slot it was picked up from — the
        // backend model never changed (only the reveal placeholder made it
        // look moved), so there's nothing to take/put; doing so anyway would
        // double-take the slot and fabricate a bogus displaced floating copy.
        if (finished.source.kind === 'existing' && locationsEqual(targetLoc, finished.source.location)) {
          return;
        }

        let incoming: ValueNode;
        if (finished.source.kind === 'fresh') {
          incoming = resolveFreshValue(finished.source.valueKind);
        } else {
          incoming = await backend.takeValue(finished.source.location);
          unmarkCapsule(finished.source.location);
        }

        // A boxed field target (operator, or a dropped-in leaf capsule) was
        // placed there on purpose, so replacing it ejects the old value as its
        // own floating card instead of silently absorbing it. An unboxed
        // (typed-in) target keeps plain put_value behavior. Read the class off
        // the live element since it already reflects ValueBlock.vue's `boxed`
        // (findDropTarget already excludes a standalone floating card's own
        // root, so `targetLoc` here is always a real slot, never that).
        if (targetEl.classList.contains('value-card-shape') || targetEl.classList.contains('value-card-shape-bool')) {
          const r = targetEl.getBoundingClientRect();
          const [x, y] = clientToCanvas(r.right + 16, r.top);
          const displaced = await backend.takeValue(targetLoc);
          await backend.putValue(targetLoc, incoming);
          markOrUnmark(targetLoc, incoming);
          await backend.createFloatingValue(x, y, displaced);
        } else {
          await backend.putValue(targetLoc, incoming);
          markOrUnmark(targetLoc, incoming);
        }
        return;
      }
      // Open canvas.
      const [x, y] = clientToCanvas(e.clientX - finished.offsetX, e.clientY - finished.offsetY);
      if (finished.source.kind === 'fresh') {
        await backend.createFloatingValue(x, y, resolveFreshValue(finished.source.valueKind), finished.source.valueKind);
      } else if (finished.source.location.kind === 'Floating' && finished.source.location.path.length === 0) {
        // Whole floating block, just repositioned. Apply the position
        // optimistically and reveal the real card immediately (same trick as
        // canvas/canvasDrag.ts's strand move), rather than waiting on
        // moveFloatingValue.
        const floatingId = finished.source.location.floating_id;
        const fv = getHost().getDocument()?.floating_values?.find(f => f.id === floatingId);
        if (fv) {
          fv.x = x;
          fv.y = y;
        }
        if (finished.hiddenAnchorEl) finished.hiddenAnchorEl.style.visibility = '';
        await backend.moveFloatingValue(floatingId, x, y);
      } else {
        const taken = await backend.takeValue(finished.source.location);
        unmarkCapsule(finished.source.location);
        await backend.createFloatingValue(x, y, taken);
      }
    } catch (err) {
      console.error('value drag drop failed:', err);
    } finally {
      // Cleared only after the backend call(s) resolve, so the source
      // slot/card never flashes back to its pre-drag content in between.
      dragReveal.value = null;
      if (finished.hiddenAnchorEl) finished.hiddenAnchorEl.style.visibility = '';
    }
  })();
}

let listenersAttached = false;

/** Wires up the document-level pointer listeners. Idempotent. */
export function attachValueDragListeners() {
  if (listenersAttached) return;
  listenersAttached = true;
  document.addEventListener('pointermove', onPointerMove);
  document.addEventListener('pointerup', onPointerUp);
  document.addEventListener('pointercancel', onPointerUp);
}
