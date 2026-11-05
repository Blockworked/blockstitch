import QtQuick

// Where blocks sit in a BlockCanvas and where a dragged stack would snap:
// block and mouth heights, the containers a stack can join, and the best
// insertion point for a ghost. Mirrors InstructionBlock's row and wrap metrics.
QtObject {
    id: snap
    required property Item canvas
    readonly property real snapThreshold: 36
    readonly property real snapSticky: 8
    function isWrapType(t) { return BlockRegistry.isWrap(t); }
    function isHeaderType(t) { return BlockRegistry.isHeader(t); }
    function isCapType(t) { return BlockRegistry.isCapType(t); }
    function isCapBlock(ins) { return BlockRegistry.isCap(ins, canvas.blockDefinitions); }
    function slotCountFor(ins) { return !ins ? 0 : ins.type === "BranchCallBlock" ? BlockRegistry.slotCount(ins) : Math.max(1, BlockRegistry.slotCount(ins)); }
    function bodyFor(ins, slot) { return BlockRegistry.body(ins, slot); }
    function blockHeight(ins) {
        if (!ins) return 58;
        const live = canvas.findBlockItem(canvas.workspaceItem, ins.id);
        if (live) return live.implicitHeight;
        if (!isWrapType(ins.type)) return isCapBlock(ins) ? 50 : 58;
        const n = slotCountFor(ins);
        let total = 0;
        for (let k = 0; k < n; ++k) total += mouthHeightFor(bodyFor(ins, k));
        return 50 + total + Math.max(0, n - 1) * 34 + 26 + 8;
    }
    function contentHeightFor(list) {
        if (!list || !list.length) return 0;
        let sum = 0;
        for (let i = 0; i < list.length; ++i) sum += blockHeight(list[i]);
        return sum - 8 * (list.length - 1);
    }
    function mouthHeightFor(list) {
        const ch = contentHeightFor(list);
        if (ch === 0) return 26;
        const last = list[list.length - 1];
        const cap = last && isCapBlock(last);
        return Math.max(26, ch - (cap ? 0 : 8));
    }
    // Block silhouette of an instruction for the attach preview: same shape
    // kind, mouth heights and flat (cap) ends a real InstructionBlock would
    // report, so the preview draws identical tabs/notches/C-shape.
    function shapeInfoFor(ins) {
        if (!ins) return { shape: "stack", mouths: [], flat: [] };
        const t = ins.type || "";
        if (isHeaderType(t)) return { shape: "header", mouths: [], flat: [] };
        if (isCapBlock(ins)) return { shape: "cap", mouths: [], flat: [] };
        if (!isWrapType(t)) return { shape: "stack", mouths: [], flat: [] };
        const n = slotCountFor(ins);
        const mouths = [], flat = [];
        for (let k = 0; k < n; ++k) {
            const body = bodyFor(ins, k);
            mouths.push(mouthHeightFor(body));
            flat.push(body.length > 0 && isCapBlock(body[body.length - 1]));
        }
        return { shape: "wrap", mouths: mouths, flat: flat };
    }
    function listFor(strand, basePath) {
        let list = (strand && strand.instructions) || [];
        const base = basePath || [];
        for (let i = 0; i < base.length; ++i) {
            const st = base[i] || {};
            const blk = list[st.index];
            if (!blk) return [];
            list = bodyFor(blk, st.slot || 0);
        }
        return list || [];
    }
    function instructionAt(strand, path) {
        if (!strand || !path || !path.length) return null;
        let list = strand.instructions || [];
        for (let i = 0; i < path.length; ++i) {
            const step = path[i];
            if (!list || step.index < 0 || step.index >= list.length) return null;
            const block = list[step.index];
            if (i === path.length - 1) return block;
            list = bodyFor(block, step.slot || 0);
        }
        return null;
    }
    function copyPath(p) {
        if (!p) return [];
        const out = [];
        for (let i = 0; i < p.length; ++i) {
            const s = p[i] || {};
            if (s.slot === undefined || s.slot === null) out.push({ index: s.index });
            else out.push({ index: s.index, slot: s.slot });
        }
        return out;
    }
    function stepsEqual(a, b) {
        if (a.index !== b.index) return false;
        const sa = (a.slot === undefined || a.slot === null) ? null : a.slot;
        const sb = (b.slot === undefined || b.slot === null) ? null : b.slot;
        return sa === sb;
    }
    function baseEqual(a, b) {
        const aa = a || [], bb = b || [];
        if (aa.length !== bb.length) return false;
        for (let i = 0; i < aa.length; ++i) if (!stepsEqual(aa[i], bb[i])) return false;
        return true;
    }
    // Snap geometry only changes with the document, the origin or as blocks
    // build, not per drag step: walking a long strand each step cost
    // hundreds of milliseconds. Plain JS so nothing re-evaluates on it.
    readonly property var _snapCache: ({ key: null })
    function snapGeometry() {
        const key = [canvas.strands, canvas.originOffsetX, canvas.originOffsetY, BlockRegistry.indexSerial,
                     canvas.branchDragState.strandId, JSON.stringify(canvas.branchDragState.path || []), canvas.branchDragState.draggedWidth];
        const c = _snapCache;
        if (!c.key || c.key.some((v, i) => v !== key[i])) { c.key = key; c.containers = null; c.tail = null; }
        return c;
    }
    function collectContainers() {
        const out = [];
        const strands = canvas.strands || [];
        for (let s = 0; s < strands.length; ++s) {
            const st = strands[s];
            const topList = st.instructions || [];
            const topHeights = [];
            for (let i = 0; i < topList.length; ++i) topHeights.push(blockHeight(topList[i]));
            const lx = st.x + canvas.originOffsetX, ly = st.y + canvas.originOffsetY;
            out.push({ strandId: st.id, basePath: [], x: lx, y: ly, list: topList, heights: topHeights });
            let top = ly;
            for (let j = 0; j < topList.length; ++j) {
                collectChildren(st.id, topList[j], [{ index: j }], lx, top, 1, out);
                top += topHeights[j] - 8;
            }
        }
        const branches = [];
        canvas.branchContainers(canvas.workspaceItem, branches);
        for (const branch of branches) {
            out.push(branch);
            let y = branch.y;
            for (let i = 0; i < branch.list.length; ++i) {
                collectChildren(branch.strandId, branch.list[i], [{ index: i }], branch.x, y, 1, out);
                y += branch.heights[i] - 8;
            }
        }
        return out;
    }
    function collectChildren(strandId, ins, pathToBlock, blockX, blockY, depth, out) {
        if (!ins || !isWrapType(ins.type)) return;
        const n = slotCountFor(ins);
        const mouthHs = [];
        for (let k = 0; k < n; ++k) mouthHs.push(mouthHeightFor(bodyFor(ins, k)));
        const live = canvas.findBlockItem(canvas.workspaceItem, ins.id);
        let mTop = live ? live.headHeight : 50;
        for (let k = 0; k < n; ++k) {
            const cX = blockX + 20, cY = blockY + mTop;
            const body = bodyFor(ins, k);
            const base = copyPath(pathToBlock);
            base[base.length - 1].slot = k;
            const heights = [];
            for (let i = 0; i < body.length; ++i) heights.push(blockHeight(body[i]));
            out.push({ strandId: strandId, basePath: base, x: cX, y: cY, list: body, heights: heights });
            let childTop = cY;
            for (let ci = 0; ci < body.length; ++ci) {
                const childPath = copyPath(base);
                childPath.push({ index: ci });
                collectChildren(strandId, body[ci], childPath, cX, childTop, depth + 1, out);
                childTop += heights[ci] - 8;
            }
            mTop = live && k + 1 < n ? live.mouthTop(k + 1) : mTop + mouthHs[k] + 34;
        }
    }
    function isBaseInsideTail(containerBase, srcParentBase, srcIdx) {
        const cb = containerBase || [], pb = srcParentBase || [];
        if (baseEqual(cb, pb)) return false;
        if (cb.length <= pb.length) return false;
        for (let i = 0; i < pb.length; ++i) if (!stepsEqual(cb[i], pb[i])) return false;
        const next = cb[pb.length];
        return next.index >= srcIdx;
    }
    // Stacked blocks interlock by the 8px connector tab (Column spacing
    // -8): a dropped block's top sits exactly on the old row top it replaces
    // (or 8px above the old bottom edge at the end / on the mouth origin when
    // empty), and everything after it moves by height-8, not height.
    function findSnap(ghostLeft, ghostTop, sourceId, sourcePath, isWhole, prevSnap, stackHeight, stackEndsCap) {
        const geometry = snapGeometry();
        const containers = geometry.containers || (geometry.containers = collectContainers());
        let best = null, bestEff = 1e9;
        const srcParentBase = (sourceId && sourcePath && sourcePath.length) ? sourcePath.slice(0, sourcePath.length - 1) : null;
        const srcIdx = (sourceId && sourcePath && sourcePath.length) ? sourcePath[sourcePath.length - 1].index : -1;
        for (let ci = 0; ci < containers.length; ++ci) {
            const c = containers[ci];
            if (sourceId && c.owner) {
                let own = false;
                for (let owner = c.owner; owner; owner = owner.parent) {
                    if (owner.strandId === sourceId && owner.path && sourcePath
                        && isBaseInsideTail(owner.path, srcParentBase || [], srcIdx)) { own = true; break; }
                }
                if (own) continue;
            }
            if (sourceId && isWhole && c.strandId === sourceId) continue;
            let list = c.list, heights = c.heights;
            if (sourceId && !isWhole && c.strandId === sourceId) {
                if (baseEqual(c.basePath, srcParentBase)) {
                    list = list.slice(0, Math.max(0, srcIdx));
                    heights = heights.slice(0, Math.max(0, srcIdx));
                } else if (isBaseInsideTail(c.basePath, srcParentBase, srcIdx)) {
                    continue;
                }
            }
            if (Math.abs(ghostLeft - c.x) > snapThreshold) continue;
            const isTop = c.basePath.length === 0;
            const headIsHeader = isTop && list.length > 0 && isHeaderType(list[0].type);
            const bounds = [];
            if (!list.length) {
                bounds.push({ index: 0, y: c.y });
            } else {
                let y = c.y;
                for (let i = 0; i < list.length; ++i) { bounds.push({ index: i, y: y }); y += heights[i] - 8; }
                bounds.push({ index: list.length, y: y });
            }
            for (let bi = 0; bi < bounds.length; ++bi) {
                const b = bounds[bi], idx = b.index;
                if (idx === 0 && headIsHeader) continue;
                if (idx > 0) {
                    const above = list[idx - 1];
                    if (!above || isCapBlock(above)) continue;
                }
                if (stackEndsCap && idx < list.length) continue;
                let dist = Math.abs(ghostTop - b.y);
                // Match the bottom connector only at the start of a body or stack.
                // Interior insertions follow the dragged top to avoid jumping ahead.
                // Bottom matches stay within half the mouth's 20px indentation.
                const alignedBottom = (isTop && !c.owner) || Math.abs(ghostLeft - c.x) < 10;
                const bottomDist = alignedBottom && idx === 0 && list.length > 0 && !stackEndsCap && stackHeight > 0
                    ? Math.abs(ghostTop + stackHeight - 8 - b.y) : Infinity;
                const prepend = isTop && !c.owner && idx === 0 && list.length > 0 && stackHeight > 0;
                // Prepending keeps the target fixed, so only its top connector
                // may meet the dragged stack's bottom connector.
                dist = prepend ? bottomDist : Math.min(dist, bottomDist);
                if (dist > snapThreshold) continue;
                const path = copyPath(c.basePath);
                path.push({ index: idx });
                const isCur = prevSnap && prevSnap.targetId === c.strandId && baseEqual(prevSnap.path, path);
                const distance = Math.hypot(ghostLeft - c.x, dist);
                const eff = isCur ? Math.max(0, distance - snapSticky) : distance;
                if (best === null || eff < bestEff) {
                    const shift = prepend ? stackHeight - 8 : 0;
                    best = { targetId: c.strandId, path: path, x: c.x, y: b.y - shift,
                        targetY: prepend ? Math.round(c.y - canvas.originOffsetY - shift) : null,
                        empty: list.length === 0, atEnd: idx === list.length };
                    bestEff = eff;
                }
            }
        }
        return best;
    }
}
