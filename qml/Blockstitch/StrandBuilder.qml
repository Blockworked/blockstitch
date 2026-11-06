import QtQuick

// Builds a BlockCanvas's strands lazily: strands and their top-level blocks
// near the view first, the rest in the background, so a big macro shows up
// before blocks nobody is looking at yet.
QtObject {
    id: builder
    required property Item canvas
    required property Flickable flick
    required property Repeater strands
    // Top-level block slots still waiting, nearest first once ordered.
    property var waitingQueue: []
    property string queueKey: ""
    property bool queueDirty: false
    function start() { timer.start(); }
    function buildStrand(strand) {
        if (!strand || strand.built)
            return;
        strand.loading = true;
        strand.estY = 0;
        strand.built = true;
        // A strand made with the canvas fills its blocks a little later.
        Qt.callLater(() => {
            if (strand)
                strand.loading = false;
        });
        canvas.builtStrands++;
    }
    // Many blocks joining a built strand at once (an attach) build like a
    // new strand: what's near the view now, the rest in the background.
    function bulkInsert(strand, repeater, at, n) {
        if (!canvas.lazyStrands || n < 20 || !strand.built || strand.loading)
            return;
        const next = repeater.itemAt(at), prev = at > 0 ? repeater.itemAt(at - 1) : null;
        strand.estY = next ? next.y : prev ? prev.y + prev.height - 8 : 0;
        strand.loading = true;
        Qt.callLater(() => {
            if (strand)
                strand.loading = false;
        });
    }
    // A top-level block slot of a strand. While the strand is first being
    // filled, only slots near the view build; later ones (edits) build at once.
    function slotCreated(strand, slot, estH) {
        const y = strand.estY;
        strand.estY += estH - 8;
        if (!canvas.lazyStrands || !strand.loading || canvas.nearView(strand.x, strand.y + y, canvas.strandEstW, estH)) {
            slot.built = true;
            return;
        }
        waitingQueue.push(slot);
        queueDirty = true;
        timer.start();
    }
    function waitingSlots() {
        waitingQueue = waitingQueue.filter(s => s && s.built === false);
        return waitingQueue;
    }
    // How many strands still wait for their blocks.
    function pendingStrands() {
        let n = 0;
        for (let i = 0; i < strands.count; ++i)
            if (strands.itemAt(i) && !strands.itemAt(i).built)
                ++n;
        return n;
    }
    // Strands and top-level blocks still waiting to be built.
    function pendingBuilds() {
        return pendingStrands() + waitingSlots().length;
    }
    // Builds every strand now, for callers that need each block to exist.
    function buildAllStrands() {
        for (let i = 0; i < strands.count; ++i)
            buildStrand(strands.itemAt(i));
        for (const s of waitingSlots())
            s.built = true;
        waitingQueue = [];
        timer.stop();
        canvas.builtStrands++;
    }
    // Builds what waits, nearest to the view first: one strand a pass, or
    // blocks of long strands for a few milliseconds, so the view shows up
    // before blocks nobody is looking at yet.
    property Timer timer: Timer {
        interval: 0
        onTriggered: {
            const z = builder.canvas.zoom || 1;
            const cx = (builder.flick.contentX + builder.flick.width / 2) / z, cy = (builder.flick.contentY + builder.flick.height / 2) / z;
            const dist = (x, y, w, h) => {
                const dx = Math.max(x - cx, 0, cx - x - w), dy = Math.max(y - cy, 0, cy - y - h);
                return dx * dx + dy * dy;
            };
            let best = null, bestD = Infinity;
            for (let i = 0; i < builder.strands.count; ++i) {
                const s = builder.strands.itemAt(i);
                if (!s || s.built)
                    continue;
                const d = dist(s.x, s.y, s.width, s.height);
                if (d < bestD) {
                    bestD = d;
                    best = s;
                }
            }
            if (best) {
                builder.buildStrand(best);
                builder.timer.start();
                return;
            }
            // Ordered once, and again only when the view moves or slots
            // join; a long strand would otherwise lay out and sort each pass.
            const key = Math.round(cx / 200) + "," + Math.round(cy / 200);
            let queue = builder.waitingQueue;
            if (queue.length && (builder.queueKey !== key || builder.queueDirty)) {
                queue = queue.filter(s => s && s.built === false);
                const seen = new Set();
                for (const s of queue)
                    if (!seen.has(s.strandItem)) {
                        seen.add(s.strandItem);
                        s.strandItem.forceLayout();
                    }
                // Bucketed by distance in 100px rings rather than sorted: a
                // JS comparator costs a call per comparison, seconds in all.
                const rings = {};
                for (const s of queue) {
                    const r = Math.min(Math.floor(Math.sqrt(dist(s.strandItem.x + s.x, s.strandItem.y + s.y, s.width, s.height)) / 100), 1e6);
                    (rings[r] || (rings[r] = [])).push(s);
                }
                queue = [];
                for (const r of Object.keys(rings).map(Number).sort((a, b) => a - b))
                    queue = queue.concat(rings[r]);
                builder.queueKey = key;
                builder.queueDirty = false;
            }
            const t0 = Date.now();
            let i = 0;
            while (i < queue.length && Date.now() - t0 < 30) {
                const s = queue[i++];
                if (s && s.built === false)
                    s.built = true;
            }
            builder.waitingQueue = queue.slice(i);
            if (i)
                builder.canvas.builtStrands++;
            if (builder.waitingQueue.length)
                builder.timer.start();
        }
    }
}
