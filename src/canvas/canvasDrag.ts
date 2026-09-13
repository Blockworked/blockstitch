// Imperative Scratch-style strand-canvas drag/drop/pan/zoom machinery.
// Deliberately not a reactive/declarative implementation — it's a real-time
// pointer/DOM-measurement state machine Vue's reactivity graph has no
// visibility into.
import type { CommentLike, StrandLike } from './host';
import { getHost, isLocked } from './host';
import { closeAllDropdowns } from '../ui/dropdownRegistry';
import type { BlockNode, NodePath, PathStep } from '../graph/blockGraph';
import { isCapType, isHeaderType } from '../graph/shapeRegistry';
import { resolveInstructionList } from '../graph/blockGraph';

// Structural equality for two path *prefixes* (a basePath, not necessarily a
// full instruction address) — `slot` is normalized so an omitted/undefined
// slot compares equal to itself regardless of which side omitted it.
function pathPrefixEqual(a: PathStep[], b: PathStep[]): boolean {
  return a.length === b.length && a.every((s, i) => s.index === b[i].index && (s.slot ?? null) === (b[i].slot ?? null));
}

function parseBasePath(el: HTMLElement): PathStep[] | null {
  try {
    return JSON.parse(el.dataset.path ?? '[]');
  } catch {
    return null;
  }
}

/** Finds the `.instruction-list` DOM container addressed by `basePath` — a
 * strand's own top-level list (`basePath: []`) or a nested wrap-block body. */
function findListContainer(strandId: string, basePath: PathStep[]): HTMLElement | null {
  const containers = document.querySelectorAll<HTMLElement>('.instruction-list');
  for (const el of containers) {
    if (el.dataset.strandId !== strandId) continue;
    const parsed = parseBasePath(el);
    if (parsed && pathPrefixEqual(parsed, basePath)) return el;
  }
  return null;
}

// Strand x/y can go negative; canvas-inner is sized to the strands' bounding
// box each render, padded so cards never touch the edge.
const CANVAS_PAD = 400;
// Bounds always extend at least this far past the origin, so there's room
// to pan even when a document has only one strand at (0, 0).
const ROOT_MARGIN = 1000;

function cssEscape(s: string): string {
  return String(s).replace(/[^a-zA-Z0-9_-]/g, '\\$&');
}

function findStrand(strandId: string): StrandLike | undefined {
  return getHost().getDocument()?.strands?.find(st => st.id === strandId);
}

// ── Comment anchoring ───────────────────────────────────────────────────────
// An attached comment's stored (x, y) is an *offset* from its instruction's
// current on-screen position — the host has no idea where a given
// instruction row renders (that depends on sibling field widths, nesting,
// etc.), so resolving "where does this comment sit" is purely a frontend
// DOM-measurement concern, same spirit as everything else in this file.

/** Sums `offsetLeft`/`offsetTop` from `el` up to (but not including)
 * `ancestor`, walking the `offsetParent` chain — `el`'s position relative to
 * `ancestor`, in the same unscaled layout-pixel space `strand.x`/`y` use. */
function offsetWithin(el: HTMLElement, ancestor: HTMLElement): [number, number] {
  let x = 0, y = 0;
  let node: HTMLElement | null = el;
  while (node && node !== ancestor) {
    x += node.offsetLeft;
    y += node.offsetTop;
    node = node.offsetParent as HTMLElement | null;
  }
  return [x, y];
}

/** Canvas-space (x, y) the instruction `instructionId` currently renders at
 * — the anchor an attached comment's stored offset is added to. `null` if
 * that instruction isn't currently rendered (e.g. its strand card hasn't
 * mounted yet this frame) or its strand can't be found. */
function attachedInstructionAnchor(instructionId: string): [number, number] | null {
  const inner = document.getElementById('canvas-inner');
  const rowEl = inner?.querySelector<HTMLElement>(`[data-instr-id="${cssEscape(instructionId)}"]`);
  if (!rowEl) return null;
  const cardEl = rowEl.closest<HTMLElement>('.strand-card');
  const strandId = cardEl?.dataset.strandId;
  const strand = strandId ? findStrand(strandId) : null;
  if (!cardEl || !strand) return null;
  const [offX, offY] = offsetWithin(rowEl, cardEl);
  return [strand.x + offX, strand.y + offY];
}

const SVG_NS = 'http://www.w3.org/2000/svg';

/** Draws (or removes) the callout line between each attached comment and its
 * instruction, in `#comment-connector-layer` — a plain SVG overlay sized to
 * match `#canvas-inner` exactly, so its own coordinates are already in the
 * same shifted canvas-inner space `commentBase`/`minX`/`minY` produce. Reuses
 * one `<line>` per comment id across calls instead of tearing down and
 * rebuilding the whole layer every frame. */
function updateCommentConnectors(
  comments: CommentLike[],
  commentCardEls: Map<string, HTMLElement>,
  commentBase: Map<string, [number, number]>,
  minX: number,
  minY: number,
) {
  const svg = document.getElementById('comment-connector-layer');
  if (!svg) return;
  const seen = new Set<string>();
  for (const c of comments) {
    if (!c.attached_to) continue;
    const card = commentCardEls.get(c.id);
    const base = commentBase.get(c.id);
    const anchor = attachedInstructionAnchor(c.attached_to);
    if (!card || !base || !anchor) continue;
    seen.add(c.id);
    let line = svg.querySelector<SVGLineElement>(`line[data-comment-id="${cssEscape(c.id)}"]`);
    if (!line) {
      line = document.createElementNS(SVG_NS, 'line');
      line.dataset.commentId = c.id;
      line.setAttribute('class', 'comment-connector-line');
      svg.appendChild(line);
    }
    const rowEl = document.getElementById('canvas-inner')?.querySelector<HTMLElement>(`[data-instr-id="${cssEscape(c.attached_to)}"]`);
    const rowW = rowEl?.offsetWidth ?? 0;
    const rowH = rowEl?.offsetHeight ?? 0;
    line.setAttribute('x1', `${anchor[0] + rowW / 2 - minX + CANVAS_PAD}`);
    line.setAttribute('y1', `${anchor[1] + rowH / 2 - minY + CANVAS_PAD}`);
    line.setAttribute('x2', `${base[0] + card.offsetWidth / 2 - minX + CANVAS_PAD}`);
    line.setAttribute('y2', `${base[1] + card.offsetHeight / 2 - minY + CANVAS_PAD}`);
  }
  for (const line of Array.from(svg.querySelectorAll<SVGLineElement>('line[data-comment-id]'))) {
    if (!seen.has(line.dataset.commentId ?? '')) line.remove();
  }
}

// ── Zoom (ctrl+scroll) ──────────────────────────────────────────────────────
// canvas-inner stays laid out at unscaled coordinates and is visually scaled
// via CSS transform; canvas-sizer's box matches the zoomed footprint so
// scrollbars match what's on screen.
const MIN_ZOOM = 0.35;
const MAX_ZOOM = 2.5;
let canvasZoom = 1;
let currentDocId: string | null = null;

// Value-block drag ghosts (valueDrag.ts) live outside canvas-inner's scaled
// subtree too, so they need this to counter-scale themselves.
export function getCanvasZoom(): number {
  return canvasZoom;
}

// Bounds of the last render, needed to convert pointer/client coordinates
// back into canvas (strand.x/y) space when a drag ends on empty canvas.
let lastBounds = { minX: 0, minY: 0 };

/** DOM geometry pass: measures rendered strand cards and positions them in
 * canvas space. Call after Vue patches the DOM (e.g. a `flush: 'post'` watcher). */
export function positionCanvas(docId: string | null | undefined) {
  const inner = document.getElementById('canvas-inner');
  const sizer = document.getElementById('canvas-sizer');
  const scrollEl = document.getElementById('canvas-scroll');
  if (!inner || !sizer || !scrollEl) return;

  const doc = getHost().getDocument();
  const strands = doc?.strands ?? [];
  const floatingValues = doc?.floating_values ?? [];
  const comments = doc?.comments ?? [];
  if ((docId ?? null) !== currentDocId) canvasZoom = 1;

  const cardEls = new Map<string, HTMLElement>();
  for (const strand of strands) {
    const el = inner.querySelector<HTMLElement>(`.strand-card[data-strand-id="${cssEscape(strand.id)}"]`);
    if (el) cardEls.set(strand.id, el);
  }
  const floatingCardEls = new Map<string, HTMLElement>();
  for (const fv of floatingValues) {
    const el = inner.querySelector<HTMLElement>(`.value-floating-card[data-floating-id="${cssEscape(fv.id)}"]`);
    if (el) floatingCardEls.set(fv.id, el);
  }
  const commentCardEls = new Map<string, HTMLElement>();
  // Raw canvas-space (x, y) each comment resolves to this frame — an
  // attached comment's own stored (x, y) is only the offset (see
  // attachedInstructionAnchor's doc comment), so this is computed once here
  // and reused for both the bounds pass below and the connector-line pass
  // at the end, rather than re-deriving it twice.
  const commentBase = new Map<string, [number, number]>();
  for (const c of comments) {
    const el = inner.querySelector<HTMLElement>(`.comment-card[data-comment-id="${cssEscape(c.id)}"]`);
    if (!el) continue;
    commentCardEls.set(c.id, el);
    if (c.attached_to) {
      const anchor = attachedInstructionAnchor(c.attached_to);
      if (!anchor) continue; // block not rendered this frame — skip, keep last position
      commentBase.set(c.id, [anchor[0] + c.x, anchor[1] + c.y]);
    } else {
      commentBase.set(c.id, [c.x, c.y]);
    }
  }

  const prevMinX = lastBounds.minX;
  const prevMinY = lastBounds.minY;
  let minX = -ROOT_MARGIN, minY = -ROOT_MARGIN, maxX = ROOT_MARGIN, maxY = ROOT_MARGIN;
  for (const strand of strands) {
    const card = cardEls.get(strand.id);
    if (!card) continue;
    minX = Math.min(minX, strand.x);
    minY = Math.min(minY, strand.y);
    maxX = Math.max(maxX, strand.x + card.offsetWidth);
    maxY = Math.max(maxY, strand.y + card.offsetHeight);
  }
  for (const fv of floatingValues) {
    const card = floatingCardEls.get(fv.id);
    if (!card) continue;
    minX = Math.min(minX, fv.x);
    minY = Math.min(minY, fv.y);
    maxX = Math.max(maxX, fv.x + card.offsetWidth);
    maxY = Math.max(maxY, fv.y + card.offsetHeight);
  }
  for (const c of comments) {
    const card = commentCardEls.get(c.id);
    const base = commentBase.get(c.id);
    if (!card || !base) continue;
    minX = Math.min(minX, base[0]);
    minY = Math.min(minY, base[1]);
    maxX = Math.max(maxX, base[0] + card.offsetWidth);
    maxY = Math.max(maxY, base[1] + card.offsetHeight);
  }
  lastBounds = { minX, minY };

  const innerW = maxX - minX + 2 * CANVAS_PAD;
  const innerH = maxY - minY + 2 * CANVAS_PAD;
  inner.style.width = `${innerW}px`;
  inner.style.height = `${innerH}px`;
  inner.style.transform = `scale(${canvasZoom})`;
  sizer.style.width = `${innerW * canvasZoom}px`;
  sizer.style.height = `${innerH * canvasZoom}px`;
  // A strand beyond the previous extent pushes minX/minY outward, shifting
  // every card's position — compensate scroll so nothing visibly jumps.
  if (minX !== prevMinX || minY !== prevMinY) {
    scrollEl.scrollLeft += (prevMinX - minX) * canvasZoom;
    scrollEl.scrollTop += (prevMinY - minY) * canvasZoom;
  }

  for (const strand of strands) {
    const card = cardEls.get(strand.id);
    if (!card) continue;
    card.style.left = `${strand.x - minX + CANVAS_PAD}px`;
    card.style.top = `${strand.y - minY + CANVAS_PAD}px`;
  }
  for (const fv of floatingValues) {
    const card = floatingCardEls.get(fv.id);
    if (!card) continue;
    card.style.left = `${fv.x - minX + CANVAS_PAD}px`;
    card.style.top = `${fv.y - minY + CANVAS_PAD}px`;
  }
  for (const c of comments) {
    const card = commentCardEls.get(c.id);
    const base = commentBase.get(c.id);
    if (!card || !base) continue;
    card.style.left = `${base[0] - minX + CANVAS_PAD}px`;
    card.style.top = `${base[1] - minY + CANVAS_PAD}px`;
  }
  updateCommentConnectors(comments, commentCardEls, commentBase, minX, minY);

  // A split-drag's new strand can render as a real, visible card at the split
  // point before drop — hide it for the drag's duration (same idea as the
  // whole-strand-grab ghost). resolvedId is set async by splitStrand, but a
  // document update can arrive first, so preExistingStrandIds catches it too.
  if (drag && !drag.restoreCard) {
    const targetId = drag.resolvedId;
    if (targetId) {
      const newCard = cardEls.get(targetId);
      if (newCard && newCard !== drag.hiddenNewCardEl) {
        newCard.style.visibility = 'hidden';
        drag.hiddenNewCardEl = newCard;
      }
    } else {
      // resolvedId not yet available — hide any strand that wasn't there
      // before the drag started (the newly created split strand).
      for (const [id, card] of cardEls) {
        if (!drag.preExistingStrandIds.has(id) && card !== drag.hiddenNewCardEl) {
          card.style.visibility = 'hidden';
          drag.hiddenNewCardEl = card;
        }
      }
    }
  }

  if ((docId ?? null) !== currentDocId) {
    currentDocId = docId ?? null;
    requestAnimationFrame(() => {
      // Center the initial view on the canvas origin — strands generally
      // spawn near (0, 0).
      scrollEl.scrollLeft = Math.max(0, -minX + CANVAS_PAD - 60);
      scrollEl.scrollTop = Math.max(0, -minY + CANVAS_PAD - 60);
    });
  }
}

// Shared by wheel-zoom and the zoom buttons: rescales around a fixed client
// point (mouse position for wheel, viewport center for the buttons) so that
// point stays visually still.
function zoomBy(factor: number, clientX: number, clientY: number) {
  const scrollEl = document.getElementById('canvas-scroll');
  if (!scrollEl) return;
  const rect = scrollEl.getBoundingClientRect();
  const canvasPtX = (clientX - rect.left + scrollEl.scrollLeft) / canvasZoom;
  const canvasPtY = (clientY - rect.top + scrollEl.scrollTop) / canvasZoom;

  const newZoom = Math.min(MAX_ZOOM, Math.max(MIN_ZOOM, canvasZoom * factor));
  if (newZoom === canvasZoom) return;
  canvasZoom = newZoom;
  positionCanvas(currentDocId);

  scrollEl.scrollLeft = canvasPtX * canvasZoom - (clientX - rect.left);
  scrollEl.scrollTop = canvasPtY * canvasZoom - (clientY - rect.top);
}

function onCanvasWheel(e: WheelEvent) {
  if (!e.ctrlKey) return;
  if (!(e.target as Element)?.closest?.('#canvas-scroll')) return;
  e.preventDefault();
  const factor = e.deltaY < 0 ? 1.12 : 1 / 1.12;
  zoomBy(factor, e.clientX, e.clientY);
}

const BUTTON_ZOOM_FACTOR = 1.25;

/** Zoom-in button handler — zooms in around the canvas viewport's center. */
export function zoomInCanvas() {
  const scrollEl = document.getElementById('canvas-scroll');
  if (!scrollEl) return;
  const rect = scrollEl.getBoundingClientRect();
  zoomBy(BUTTON_ZOOM_FACTOR, rect.left + rect.width / 2, rect.top + rect.height / 2);
}

/** Zoom-out button handler — zooms out around the canvas viewport's center. */
export function zoomOutCanvas() {
  const scrollEl = document.getElementById('canvas-scroll');
  if (!scrollEl) return;
  const rect = scrollEl.getBoundingClientRect();
  zoomBy(1 / BUTTON_ZOOM_FACTOR, rect.left + rect.width / 2, rect.top + rect.height / 2);
}

/** Resets zoom to 1 and re-centers the scroll position on the canvas origin,
 * matching the view a freshly opened document starts at. */
export function resetCanvasView() {
  const scrollEl = document.getElementById('canvas-scroll');
  if (!scrollEl) return;
  canvasZoom = 1;
  positionCanvas(currentDocId);
  scrollEl.scrollLeft = Math.max(0, -lastBounds.minX + CANVAS_PAD - 60);
  scrollEl.scrollTop = Math.max(0, -lastBounds.minY + CANVAS_PAD - 60);
}

// ── Middle/left-click-drag panning ──────────────────────────────────────────
interface PanState {
  pointerId: number;
  startX: number;
  startY: number;
  startScrollLeft: number;
  startScrollTop: number;
}
let pan: PanState | null = null;

// Captures on `el` (defaulting to `e.target`) rather than always the exact
// element under the pointer at pickup — a whole-strand grab is fine either
// way, but a tail/split drag (beginPickup, non-index-0) picks up a row whose
// backend split can be confirmed and reflected in a Vue re-render well
// within the gesture's lifetime, which removes that specific `.instruction-
// row` element from the DOM entirely (it's no longer in the shortened
// source strand's list, not just restyled/hidden — see the hidden clones
// startDrag builds instead of moving the real nodes for exactly this
// reason). A capturing element that gets removed from the document loses
// capture implicitly, and — confirmed by instrumenting a real drag — this
// can happen 100-200ms in, well inside a normal drag's duration, silently
// breaking delivery of the rest of the gesture's move/up events and
// stranding the split-off strand at its temporary post-split position
// instead of wherever it was actually dropped (reads as "the drag did
// nothing"). Every caller below now captures on the stable canvas-scroll
// container instead, which the Vue tree never tears down, so no drag's
// capture can be invalidated by a reactive re-render mid-gesture.
export function capturePointer(e: PointerEvent, el?: Element | null) {
  try {
    (el ?? (e.target as Element | null))?.setPointerCapture?.(e.pointerId);
  } catch (err) {
    console.error('setPointerCapture failed:', err);
  }
}

/** The stable element every drag/pan gesture should capture its pointer on
 * — see capturePointer's doc comment for why capturing on the specific
 * element under the pointer at pickup is fragile. Never torn down by Vue
 * (it's the canvas's own static scroll viewport, not part of any v-for),
 * so a mid-gesture re-render — e.g. a split's backend confirmation landing
 * — can never invalidate capture out from under an in-progress drag. */
function stableCaptureEl(): Element | null {
  return document.getElementById('canvas-scroll');
}

// On Linux, middle click is X11's "paste primary selection" — CEF honors it
// against the focused element regardless of hit-testing, so preventDefault()
// on pointerdown doesn't stop it. Swallow the resulting ClipboardEvent
// instead while a middle-click pan is in flight.
let blockPrimaryPaste = false;
let blockPrimaryPasteGeneration = 0;

function blockMiddleClickPaste(e: ClipboardEvent) {
  if (!blockPrimaryPaste) return;
  e.preventDefault();
  e.stopImmediatePropagation();
}

function beginPan(e: PointerEvent) {
  if (e.button !== 1 && e.button !== 0) return;
  if (!(e.target as Element)?.closest?.('#canvas-scroll')) return;
  // A left-click only pans when it lands on genuinely empty canvas space —
  // an actual instruction row (or the strand's empty-strand hint), a
  // floating value card, or a comment card is left alone so beginPickup/
  // value-drag/beginCommentDrag pointerdown handlers (bound deeper in those
  // trees) keep working as normal left-click-drags. This deliberately checks
  // for real row content rather than `.strand-card` as a whole: a card's
  // bounding box is only as wide as its widest row (`.strand-body` uses
  // `align-items: flex-start`, so narrower rows don't stretch to match), so a
  // card with rows of differing widths has genuinely blank space inside its
  // box, to the right of any narrower row. That gutter isn't covered by any
  // row's own pointerdown handler, so excluding all of `.strand-card` left
  // it dead: no pan, and no preventDefault() either, so the browser fell
  // back to its native text-selection drag.
  if (e.button === 0 && (e.target as Element)?.closest?.('.instruction-row, .strand-empty-hint, .value-floating-card, .comment-card')) return;
  // preventDefault() below suppresses the compatibility `mousedown` event a
  // mouse pointerdown would otherwise fire — that's what the context menu
  // and other dropdowns listen for to close on an outside click, so without
  // this they'd only close once the pan's pointermove fires (e.g. scrolling
  // the canvas trips their own scroll-closes-menu handler), not on the
  // initiating click itself. The same suppressed default also normally
  // blurs whatever text field currently has focus (a value/field edit, a
  // comment body, ...) — since preventDefault() below cancels that too, do
  // it explicitly so clicking empty canvas space still deselects it.
  const active = document.activeElement;
  if (active instanceof HTMLElement && (active.tagName === 'INPUT' || active.tagName === 'TEXTAREA' || active.isContentEditable)) {
    active.blur();
  }
  // Blurring an active field clears its own focus, but a stray text
  // selection (e.g. from a drag that landed on selectable text) is a
  // separate browser concept that survives a blur — clear it explicitly so
  // clicking empty canvas space always leaves a clean slate.
  window.getSelection()?.removeAllRanges();
  closeAllDropdowns();
  blockPrimaryPaste = true;
  blockPrimaryPasteGeneration++;
  e.preventDefault();
  capturePointer(e, stableCaptureEl());
  const scrollEl = document.getElementById('canvas-scroll');
  if (!scrollEl) return;
  pan = {
    pointerId: e.pointerId,
    startX: e.clientX,
    startY: e.clientY,
    startScrollLeft: scrollEl.scrollLeft,
    startScrollTop: scrollEl.scrollTop,
  };
  scrollEl.classList.add('panning');
}

// ── Instruction sidebar (palette + trash) ───────────────────────────────────

export function isOverSidebar(e: PointerEvent): boolean {
  const el = document.getElementById('instruction-sidebar');
  if (!el) return false;
  const rect = el.getBoundingClientRect();
  return e.clientX >= rect.left && e.clientX <= rect.right && e.clientY >= rect.top && e.clientY <= rect.bottom;
}

export function setSidebarArmed(armed: boolean) {
  document.getElementById('instruction-sidebar')?.classList.toggle('trash-armed', armed);
}

// Toggled on `<body>` for the duration of a whole-strand or palette drag —
// see blockstitch.css's `body:not(.bs-dragging)` guards on the ordinary
// hover-highlight rules for why this exists: a drag ghost is `pointer-events:
// none`, so real hover keeps landing on whatever real row the ghost happens
// to be floating over mid-drag, lighting up unrelated (and often much
// larger, e.g. a whole If/If-Else chain) blocks blue with no relation to
// where the drag would actually land. Suppressing ordinary hover for the
// drag's duration and instead forcing the same accent treatment onto the
// ghost itself (also in blockstitch.css) makes "what's highlighted" always
// mean "what's being dragged," never "whatever it last passed over."
function setDragActive(active: boolean) {
  document.body.classList.toggle('bs-dragging', active);
}

// ── Drag pickup (grip / whole-strand) ───────────────────────────────────────
interface DragCandidate {
  strandId: string;
  path: NodePath;
  pointerId: number;
  startX: number;
  startY: number;
}
let dragCandidate: DragCandidate | null = null;

interface DragState {
  pointerId: number;
  offsetX: number;
  offsetY: number;
  ghostEl: HTMLElement;
  resolvedId: string | null;
  resolvingPromise: Promise<string | void> | null;
  snap: { targetId: string; path: NodePath } | null;
  // The strand this drag started from, always known synchronously —
  // unlike resolvedId (which for a split drag stays null until splitStrand's
  // backend round trip resolves it to the *new* tail strand's id), this
  // never depends on anything async. Needed as the snap-target exclusion
  // fallback while resolvedId is still pending: the old fallback read the
  // module-level `dragCandidate` variable, but that's already been set back
  // to null (by the same onPointerMove branch that calls startDrag) by the
  // time any pointermove reaches updateSnapTarget, so it was always
  // `undefined` — meaning nothing was excluded during that window, and the
  // strand's own still-fully-intact original position (the block hasn't
  // actually been detached from it backend-side yet) was free to win as the
  // "nearest" snap target, silently merging a split-off tail right back
  // where it started. See onPointerMove's updateSnapTarget call.
  sourceStrandId: string;
  overTrash?: boolean;
  // Set for a whole-strand grab of a header-shaped strand whose block
  // definition should be deleted (rather than just detaching the body
  // strand) when trashed — see shapeRegistry.ts's 'header' kind.
  blockId: string | null;
  // A header-shaped strand can be moved freely but never snapped/merged into
  // another (that would attach it underneath something).
  noSnap: boolean;
  // The real DOM node(s) are physically relocated into the ghost (not
  // cloned), so the strand visibly follows the pointer. Vue reuses these
  // nodes by key, so they MUST be moved back explicitly on every drag end or
  // Vue's next patch gets confused about where they live.
  restoreCard: { el: HTMLElement; parent: Node; next: Node | null } | null;
  // Partial (split) drags can't use the real-node move: splitStrand's
  // response can patch the old strand's row list mid-drag while rows sit
  // detached in the ghost, so these stay hidden clones instead.
  hiddenRowEls: HTMLElement[];
  // A resolved split's new strand renders visible at the split point almost
  // immediately; positionCanvas hides it each render — tracked here so
  // pointerup knows what to unhide.
  hiddenNewCardEl: HTMLElement | null;
  // Strand IDs that existed when the drag started — lets positionCanvas
  // detect new split-strand cards before resolvedId is set.
  preExistingStrandIds: Set<string>;
}
let drag: DragState | null = null;

interface PaletteDragState {
  pointerId: number;
  insType: string;
  // Set only for a dynamic-arity call-site drag — clonePaletteInstruction
  // can't resolve which variant from `insType` alone.
  variantId?: string;
  offsetX: number;
  offsetY: number;
  ghostEl: HTMLElement;
  snap: { targetId: string; path: NodePath } | null;
}
let paletteDrag: PaletteDragState | null = null;

// ── Comment drag (drag by its own title bar only) ───────────────────────────
interface CommentDragState {
  pointerId: number;
  commentId: string;
  offsetX: number;
  offsetY: number;
  ghostEl: HTMLElement;
  restoreCard: { el: HTMLElement; parent: Node; next: Node | null };
}
let commentDrag: CommentDragState | null = null;

/** Starts dragging a comment card — called from its own title-bar
 * pointerdown handler (CommentCard.vue), never from anywhere else on the
 * card, per the "drag by the top" spec. Moves the real card into a ghost
 * (same technique as a whole-strand grab in `startDrag`) so it visually
 * follows the pointer without touching reactive state mid-drag; the actual
 * `moveComment` call happens once, on drop. */
export function beginCommentDrag(e: PointerEvent, commentId: string) {
  if (e.button !== undefined && e.button !== 0) return;
  const cardEl = document.querySelector<HTMLElement>(`.comment-card[data-comment-id="${cssEscape(commentId)}"]`);
  if (!cardEl) return;
  e.preventDefault();
  capturePointer(e, stableCaptureEl());
  const rect = cardEl.getBoundingClientRect();
  const ghost = document.createElement('div');
  ghost.className = 'comment-drag-ghost';
  const restoreCard = { el: cardEl, parent: cardEl.parentNode as Node, next: cardEl.nextSibling };
  cardEl.style.position = 'static';
  cardEl.style.left = '';
  cardEl.style.top = '';
  ghost.appendChild(cardEl);
  document.body.appendChild(ghost);
  commentDrag = {
    pointerId: e.pointerId,
    commentId,
    offsetX: e.clientX - rect.left,
    offsetY: e.clientY - rect.top,
    ghostEl: ghost,
    restoreCard,
  };
  positionGhost(e);
}

export function beginPickup(e: PointerEvent, strandId: string, path: NodePath) {
  if (isLocked()) return;
  if (e.button !== undefined && e.button !== 0) return;
  e.preventDefault();
  capturePointer(e, stableCaptureEl());
  dragCandidate = { strandId, path, pointerId: e.pointerId, startX: e.clientX, startY: e.clientY };
}

// Dragging a palette entry previews the actual instruction block it creates
// (not the sidebar chip).
export function beginPaletteDrag(e: PointerEvent, insType: string, ghostRowEl: HTMLElement, variantId?: string) {
  if (isLocked()) return;
  if (e.button !== undefined && e.button !== 0) return;
  e.preventDefault();
  capturePointer(e, stableCaptureEl());

  const ghost = document.createElement('div');
  ghost.className = 'strand-drag-ghost';
  const ghostCard = document.createElement('div');
  ghostCard.className = 'strand-card';
  const ghostBody = document.createElement('div');
  ghostBody.className = 'strand-body';
  ghostBody.appendChild(ghostRowEl);
  ghostCard.appendChild(ghostBody);
  ghost.appendChild(ghostCard);
  document.body.appendChild(ghost);

  paletteDrag = {
    pointerId: e.pointerId,
    insType,
    variantId,
    offsetX: 14,
    offsetY: 14,
    ghostEl: ghost,
    snap: null,
  };
  setDragActive(true);
  positionGhost(e);
}

let ghostRafPending = false;
let lastPointerEvent: PointerEvent | null = null;
function positionGhost(e: PointerEvent) {
  lastPointerEvent = e;
  if (ghostRafPending) return;
  ghostRafPending = true;
  requestAnimationFrame(() => {
    ghostRafPending = false;
    const active = drag ?? paletteDrag ?? commentDrag;
    if (!active || !lastPointerEvent) return;
    const tx = lastPointerEvent.clientX - active.offsetX;
    const ty = lastPointerEvent.clientY - active.offsetY;
    active.ghostEl.style.transform = `translate(${tx}px, ${ty}px) scale(${canvasZoom})`;
    active.ghostEl.style.transformOrigin = '0 0';
  });
}

const SNAP_THRESHOLD = 36;
// How much closer a *different* boundary than the currently-snapped one has
// to be before it's allowed to take over — see updateSnapTarget's own
// comment for the oscillation this prevents.
const SNAP_STICKY_BONUS = 8;

// Shared by strand-drags and palette-drags; writes the result onto
// `target.snap` and updates the shared snap preview.
interface SnapCandidate { targetId: string; path: NodePath; dist: number; container: HTMLElement }

// A container's *real* direct-child rows — excludes the snap-preview clone
// itself (see showSnapPreview) so it never counts as a row when computing
// boundaries/indices, even though it shares the `.instruction-row` class.
function realRows(container: HTMLElement): HTMLElement[] {
  return Array.from(container.children).filter((el): el is HTMLElement => el.classList.contains('instruction-row') && el !== snapPreviewEl);
}

// Scans every `.instruction-list` container on the canvas (a strand's own
// top level, or a nested wrap-block body) independently — each contributes
// its own boundary set from only its *direct* child rows, so a nested
// body's rows never leak into an ancestor's boundaries and vice versa — then
// picks the single globally closest boundary across all of them.
//
// The snap preview is removed *before* any of this measuring happens (not
// just excluded from `realRows`'s own array — it still occupies real flex
// layout space, so leaving it in place shifts every row after it down by
// its own height while everything is being measured). Skipping that meant
// the preview's own presence fed back into the next call's measurements:
// showing it at boundary N shifted boundary N+1 (and everything after)
// down by the preview's height, which on the very next pointermove could
// make N+1 measure as the closer candidate, moving the preview there —
// which shifted things back, making N look closer again next time, and so
// on every frame regardless of whether the pointer had moved at all. That
// self-sustaining flip was the reported "flashing" near an ambiguous
// boundary (e.g. right above an empty C-slot) — measuring against the
// undisturbed layout every time removes the feedback loop entirely. The
// sticky bonus below is a second, independent safety net against the same
// symptom arising from ordinary pointer/measurement jitter (two boundaries
// a pixel or two apart from real mouse tremor, not from the preview's own
// footprint) rather than the layout-feedback case above.
function updateSnapTarget(e: PointerEvent, target: { snap: { targetId: string; path: NodePath } | null }, excludeId: string | null | undefined, ghostEl?: HTMLElement) {
  const prevSnap = target.snap;
  clearSnapPreview();

  const ghostRect = ghostEl?.getBoundingClientRect();
  const containers = Array.from(document.querySelectorAll<HTMLElement>('.instruction-list'));
  let best: SnapCandidate | null = null;
  let bestEffectiveDist = Infinity;
  for (const container of containers) {
    const id = container.dataset.strandId;
    if (!id || id === excludeId) continue;
    const cardEl = container.closest<HTMLElement>('.strand-card, .value-floating-card');
    if (!cardEl) continue;
    // This container's own left edge — not the outer strand card's. For a
    // nested wrap-block body, the actual attach point sits well to the right
    // of the card's edge (past the spine's indent), so checking against
    // cardRect.left here would make nested targets nearly unreachable.
    const containerRect = container.getBoundingClientRect();

    // Judge horizontal proximity against the list's actual attach point
    // (left edge), not a loose bounding-box overlap.
    const refX = ghostRect ? ghostRect.left : e.clientX;
    if (Math.abs(refX - containerRect.left) > SNAP_THRESHOLD) continue;

    const basePath = parseBasePath(container);
    if (!basePath) continue;

    const rows = realRows(container);
    const boundaries = rows.map(r => r.getBoundingClientRect().top);
    boundaries.push(rows.length ? rows[rows.length - 1].getBoundingClientRect().bottom : containerRect.top + 8);

    // Index 0 would attach above this list's first block — never allowed
    // when that's a header block (nothing may end up above it); only
    // possible at a strand's own top level (basePath: []), since a header
    // can never live nested inside a wrap-block body.
    const listInstructions = findStrand(id)
      ? resolveInstructionList(findStrand(id) as { id: string; instructions: BlockNode[] }, basePath)
      : rows.map(row => ({ id: row.dataset.instrId ?? '', type: row.dataset.type ?? '' }));
    const headIsHeader = basePath.length === 0 && listInstructions[0] && isHeaderType(listInstructions[0].type);
    for (let idx = 0; idx < boundaries.length; idx++) {
      if (idx === 0 && headIsHeader) continue;
      // A boundary below a cap block would attach something underneath it —
      // never allowed, since it ends this list's flow.
      if (idx > 0 && isCapType(listInstructions[idx - 1].type, listInstructions[idx - 1])) continue;
      const y = boundaries[idx];
      const refY = ghostRect ? ghostRect.top : e.clientY;
      const dist = Math.abs(refY - y);
      if (dist > SNAP_THRESHOLD) continue;
      const path = [...basePath, { index: idx }];
      // Give the boundary that's already snapped a head start, so a nearly
      // tied candidate (a pixel or two closer, from pointer jitter or
      // sub-pixel layout rounding) doesn't keep stealing the target back and
      // forth every frame — a real, meaningfully closer boundary still wins.
      const isCurrent = !!prevSnap && prevSnap.targetId === id && pathPrefixEqual(prevSnap.path, path);
      const effectiveDist = isCurrent ? Math.max(0, dist - SNAP_STICKY_BONUS) : dist;
      if (best === null || effectiveDist < bestEffectiveDist) {
        best = { targetId: id, path, dist, container };
        bestEffectiveDist = effectiveDist;
      }
    }
  }
  target.snap = best !== null ? { targetId: best.targetId, path: best.path } : null;

  if (best !== null) {
    showSnapPreview(best, ghostEl);
  }
}

let snapPreviewEl: HTMLElement | null = null;

function clearSnapPreview() {
  if (snapPreviewEl) {
    snapPreviewEl.remove();
    snapPreviewEl = null;
  }
}

// Inserted as a genuine sibling among the target list's real rows (not a
// `position: fixed` overlay floating on top of them) — a translucent clone
// of only the *first* row being dragged, so it participates in the same
// flex-column flow as everything else. That single change gets two things
// for free: every row after the drop point visibly shifts down to make
// room (exactly as if the drop had already happened), and an ancestor
// `.wrap-mouth` auto-grows to fit it, since it's just another flex child
// now. Cloning only the ghost's first row — not the whole dragged strand —
// is what caps the gap at one block even when a long multi-block strand is
// being dragged.
function showSnapPreview(best: SnapCandidate, ghostEl?: HTMLElement) {
  clearSnapPreview();

  if (!ghostEl) return;
  const ghostRow = ghostEl.querySelector('.instruction-row');
  if (!ghostRow) return;

  const clone = ghostRow.cloneNode(true) as HTMLElement;
  clone.classList.add('strand-snap-preview');
  // The clone may itself be a wrap block whose real nested body carries
  // `.instruction-list` markers (with their own data-strand-id/data-path,
  // copied verbatim by cloneNode) — strip those so updateSnapTarget's own
  // `.instruction-list` scan never mistakes this inert preview for a real
  // drop target.
  clone.querySelectorAll('.instruction-list').forEach(el => el.classList.remove('instruction-list'));

  const idx = best.path[best.path.length - 1].index;
  const rows = realRows(best.container);
  best.container.insertBefore(clone, rows[idx] ?? null);

  snapPreviewEl = clone;
}

export function clientToCanvas(clientX: number, clientY: number): [number, number] {
  const inner = document.getElementById('canvas-inner');
  if (!inner) return [0, 0];
  const rect = inner.getBoundingClientRect();
  return [
    Math.round((clientX - rect.left) / canvasZoom - CANVAS_PAD + lastBounds.minX),
    Math.round((clientY - rect.top) / canvasZoom - CANVAS_PAD + lastBounds.minY),
  ];
}

// The ghost is the real `.strand-card`/`.instruction-row` node(s), physically
// moved into it — the block dragged is literally the strand itself.
function startDrag(e: PointerEvent, candidate: DragCandidate) {
  const { strandId, path, pointerId } = candidate;
  const virtualBranch = strandId.startsWith('value-branch:');
  const strand = findStrand(strandId) ?? (virtualBranch
    ? { id: strandId, x: 0, y: 0, instructions: [] as BlockNode[] }
    : undefined);
  if (!strand) return;

  const cardEl = document.querySelector<HTMLElement>(`.strand-card[data-strand-id="${cssEscape(strandId)}"]`);
  // Only a true top-level index-0 grab picks up the whole strand card as a
  // unit — anything nested inside a wrap-block body, or a non-zero
  // top-level index, always goes through the split-off-a-tail path below.
  const wholeStrandGrab = !virtualBranch && path.length === 1 && path[0].index === 0;

  const ghost = document.createElement('div');
  ghost.className = 'strand-drag-ghost';
  let anchorRect: { left: number; top: number } = cardEl ? cardEl.getBoundingClientRect() : { left: e.clientX, top: e.clientY };
  let restoreCard: DragState['restoreCard'] = null;
  let hiddenRowEls: HTMLElement[] = [];

  if (wholeStrandGrab) {
    if (cardEl) {
      restoreCard = { el: cardEl, parent: cardEl.parentNode as Node, next: cardEl.nextSibling };
      // The card's left/top are canvas-space coordinates for its usual home;
      // drop them while on loan so the ghost's transform alone places it.
      cardEl.style.position = 'static';
      cardEl.style.left = '';
      cardEl.style.top = '';
      ghost.appendChild(cardEl);
    }
  } else {
    const basePath = path.slice(0, -1);
    const localIndex = path[path.length - 1].index;
    const container = findListContainer(strandId, basePath);
    const rowEls = container
      ? Array.from(container.children).filter((el): el is HTMLElement => el.classList.contains('instruction-row')).slice(localIndex)
      : [];
    if (rowEls[0]) anchorRect = rowEls[0].getBoundingClientRect();
    const ghostCard = document.createElement('div');
    ghostCard.className = 'strand-card';
    const ghostBody = document.createElement('div');
    ghostBody.className = 'strand-body';
    rowEls.forEach(el => {
      // Clone first, hide second — cloneNode copies inline style verbatim,
      // so hiding first would make the clone invisible too.
      const clone = el.cloneNode(true) as HTMLElement;
      clone.style.visibility = '';
      ghostBody.appendChild(clone);
      el.style.visibility = 'hidden';
    });
    ghostCard.appendChild(ghostBody);
    ghost.appendChild(ghostCard);
    hiddenRowEls = rowEls;
  }
  document.body.appendChild(ghost);

  const headInstruction = strand.instructions[0];
  const newDrag: DragState = {
    pointerId,
    offsetX: e.clientX - anchorRect.left,
    offsetY: e.clientY - anchorRect.top,
    ghostEl: ghost,
    resolvedId: null,
    resolvingPromise: null,
    snap: null,
    sourceStrandId: strandId,
    restoreCard,
    hiddenRowEls,
    hiddenNewCardEl: null,
    blockId: wholeStrandGrab && headInstruction ? (headInstruction as unknown as { block_id?: string }).block_id ?? null : null,
    noSnap: wholeStrandGrab && headInstruction != null && isHeaderType(headInstruction.type),
    preExistingStrandIds: new Set(getHost().getDocument()?.strands?.map(s => s.id) ?? []),
  };
  drag = newDrag;
  setDragActive(true);

  if (wholeStrandGrab) {
    newDrag.resolvedId = strandId;
  } else {
    newDrag.resolvingPromise = getHost().backend.splitStrand(strandId, path, strand.x + 24, strand.y + 24)
      .then(newId => {
        newDrag.resolvedId = newId;
        return newId;
      })
      .catch(err => {
        console.error('split_strand failed:', err);
      });
  }

  positionGhost(e);
}

// Each branch below confirms the event's pointerId belongs to that gesture
// before handling it, rather than a blanket "some gesture is active" check —
// a stuck gesture would otherwise swallow every other pointer's events forever.
function onPointerMove(e: PointerEvent) {
  if (pan && e.pointerId === pan.pointerId) {
    const scrollEl = document.getElementById('canvas-scroll');
    if (scrollEl) {
      scrollEl.scrollLeft = pan.startScrollLeft - (e.clientX - pan.startX);
      scrollEl.scrollTop = pan.startScrollTop - (e.clientY - pan.startY);
    }
    return;
  }
  if (commentDrag && e.pointerId === commentDrag.pointerId) {
    positionGhost(e);
    return;
  }
  if (paletteDrag && e.pointerId === paletteDrag.pointerId) {
    positionGhost(e);
    // A brand-new header block always becomes its own detached strand — it
    // can never snap into an existing one.
    if (isOverSidebar(e) || isHeaderType(paletteDrag.insType)) {
      paletteDrag.snap = null;
      clearSnapPreview();
    } else {
      updateSnapTarget(e, paletteDrag, null, paletteDrag.ghostEl);
    }
    return;
  }
  if (drag && e.pointerId === drag.pointerId) {
    positionGhost(e);
    if (isOverSidebar(e)) {
      drag.overTrash = true;
      drag.snap = null;
      clearSnapPreview();
      setSidebarArmed(true);
    } else {
      drag.overTrash = false;
      setSidebarArmed(false);
      if (drag.noSnap) {
        drag.snap = null;
        clearSnapPreview();
      } else {
        updateSnapTarget(e, drag, drag.resolvedId ?? drag.sourceStrandId, drag.ghostEl);
      }
    }
    return;
  }
  if (dragCandidate && e.pointerId === dragCandidate.pointerId) {
    const dx = e.clientX - dragCandidate.startX;
    const dy = e.clientY - dragCandidate.startY;
    if (Math.hypot(dx, dy) < 4) return;
    const candidate = dragCandidate;
    dragCandidate = null;
    startDrag(e, candidate);
  }
}

function onPointerUp(e: PointerEvent) {
  if (pan && pan.pointerId === e.pointerId) {
    pan = null;
    // The primary-selection paste fires on middle-button release slightly
    // after this handler runs, so clear the flag after a tick, not
    // synchronously. Guard with a generation counter against a fresh pan.
    const generation = blockPrimaryPasteGeneration;
    setTimeout(() => {
      if (blockPrimaryPasteGeneration === generation) blockPrimaryPaste = false;
    }, 200);
    document.getElementById('canvas-scroll')?.classList.remove('panning');
  }
  if (dragCandidate && dragCandidate.pointerId === e.pointerId) {
    dragCandidate = null;
  }

  if (commentDrag && commentDrag.pointerId === e.pointerId) {
    const finished = commentDrag;
    commentDrag = null;
    finished.restoreCard.el.style.position = '';
    finished.restoreCard.parent.insertBefore(finished.restoreCard.el, finished.restoreCard.next);
    finished.ghostEl.remove();

    const [absX, absY] = clientToCanvas(e.clientX - finished.offsetX, e.clientY - finished.offsetY);
    const comment = getHost().getDocument()?.comments?.find(c => c.id === finished.commentId);
    if (comment) {
      // Freestanding: stored (x, y) is the absolute canvas position, same as
      // a floating value. Attached: stored (x, y) is an offset from the
      // instruction's current position, so subtract that anchor back out.
      const anchor = comment.attached_to ? attachedInstructionAnchor(comment.attached_to) : null;
      const [x, y] = anchor ? [absX - anchor[0], absY - anchor[1]] : [absX, absY];
      comment.x = x;
      comment.y = y;
      void getHost().backend.moveComment(finished.commentId, x, y);
    }
    return;
  }

  if (paletteDrag && paletteDrag.pointerId === e.pointerId) {
    const finished = paletteDrag;
    paletteDrag = null;
    setDragActive(false);
    clearSnapPreview();
    finished.ghostEl.remove();

    if (!isOverSidebar(e)) {
      const ins = getHost().clonePaletteInstruction(finished.insType, finished.variantId);
      void (async () => {
        try {
          if (finished.snap) {
            await getHost().backend.addInstruction(finished.snap.targetId, finished.snap.path, ins);
          } else {
            const [x, y] = clientToCanvas(e.clientX - finished.offsetX, e.clientY - finished.offsetY);
            await getHost().backend.addStrand(x, y, ins);
          }
        } catch (err) {
          console.error('palette drop failed:', err);
        }
      })();
    }
    return;
  }

  if (!drag || drag.pointerId !== e.pointerId) return;

  const finished = drag;
  drag = null;
  setDragActive(false);
  clearSnapPreview();
  setSidebarArmed(false);
  // Move the real card back before removing the ghost wrapper —
  // unconditionally, so Vue finds it where its vnode tree expects on the
  // next patch (the async backend round trip may never re-render it at all).
  if (finished.restoreCard) {
    finished.restoreCard.el.style.position = '';
    finished.restoreCard.parent.insertBefore(finished.restoreCard.el, finished.restoreCard.next);
  }
  // Remove the ghost first so the real card at the split point isn't
  // briefly visible alongside the ghost's clones.
  finished.ghostEl.remove();
  // The split-drag rows were only hidden (parent never changed), so unhide
  // them here (see hiddenRowEls on DragState for why they can't be moved
  // like the card). References may be stale post-resolve, but unhiding is harmless.
  for (const el of finished.hiddenRowEls) el.style.visibility = '';
  // Don't unhide hiddenNewCardEl here — merge/trash removes the strand so it
  // stays hidden; move unhides it after the optimistic x/y update below.

  void (async () => {
    const id = finished.resolvedId ?? (finished.resolvingPromise ? await finished.resolvingPromise : null);
    if (!id) return;
    const { backend } = getHost();
    if (finished.overTrash) {
      // A custom block's header strand: delete the block definition (which
      // removes the body strand and every call site) rather than just
      // detaching it.
      if (finished.blockId && backend.deleteBlockDef) {
        await backend.deleteBlockDef(finished.blockId);
      } else {
        await backend.removeStrand(id);
      }
    } else if (finished.snap) {
      await backend.mergeStrand(id, finished.snap.targetId, finished.snap.path);
    } else {
      const [x, y] = clientToCanvas(e.clientX - finished.offsetX, e.clientY - finished.offsetY);
      // Optimistic: apply locally so the card renders at the drop point
      // immediately instead of "teleporting" once the round trip lands.
      const strand = findStrand(id);
      if (strand) {
        strand.x = x;
        strand.y = y;
      }
      // Reveal the card now that it's positioned at the drop coordinates,
      // so it never appears at the split point.
      if (finished.hiddenNewCardEl) finished.hiddenNewCardEl.style.visibility = '';
      await backend.moveStrand(id, x, y);
    }
  })();
}

let listenersAttached = false;

/** Wires up the document/canvas-scroll-level pointer listeners. Idempotent. */
export function attachDragListeners() {
  if (listenersAttached) return;
  listenersAttached = true;
  document.addEventListener('pointerdown', beginPan);
  document.addEventListener('pointermove', onPointerMove);
  document.addEventListener('pointerup', onPointerUp);
  document.addEventListener('pointercancel', onPointerUp);
  document.addEventListener('paste', blockMiddleClickPaste, true);
  document.addEventListener('wheel', onCanvasWheel, { passive: false });
}
