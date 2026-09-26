import QtQuick
import QtQuick.Shapes

// Paints a block silhouette: a fill with a beveled gradient and an outline.
// "stack" / "header" / "cap" are single rows; "wrap" is a C-shaped block
// (head bar, one mouth per body, mid bars between bodies, foot bar) whose inner
// connector notches/tabs line up with the blocks nested in its mouths.
// A Shape rather than a Canvas: a canvas per block is a texture per block,
// repainted on the CPU on every hover, and blurred by the canvas zoom.
Shape {
    id: root
    property string shape: "stack"
    property color fill: Theme.block
    property color outline: Theme.border
    property color hoverColor: Theme.accent
    property bool hovered: false

    // wrap geometry: bar *body* heights (the bottom connector tab protrudes
    // `tab` px below the foot bar) and one entry per mouth
    property real headHeight: 50
    property real midHeight: 34
    property real footHeight: 26
    property real spine: 20
    property var mouthHeights: []
    property var flatEnds: []   // per mouth: last nested block has no bottom tab, so the bar below it has no notch
    readonly property real tab: 8

    preferredRendererType: Shape.CurveRenderer

    // connector profile, relative to the connector's left edge: [x, depth]
    readonly property var profile: [[0, 0], [4, 5], [8, 8], [18, 8], [22, 5], [26, 0]]

    function notch(ctx, x0, y) { for (let i = 0; i < 6; ++i) ctx.lineTo(x0 + profile[i][0], y + profile[i][1]); }
    function tabTo(ctx, x0, y) { for (let i = 5; i >= 0; --i) ctx.lineTo(x0 + profile[i][0], y + profile[i][1]); }

    function trace(ctx) {
        const ins = .6, r = 5, w = width, h = height;
        const L = ins, R = w - ins, T = ins;
        if (shape !== "wrap") {
            const topNotch = shape !== "header", bottomTab = shape !== "cap";
            const base = (bottomTab ? h - tab : h) - ins;
            ctx.moveTo(L + r, T);
            if (topNotch) { ctx.lineTo(13, T); notch(ctx, 13, T); }
            ctx.lineTo(R - r, T); ctx.quadraticCurveTo(R, T, R, T + r);
            ctx.lineTo(R, base - r); ctx.quadraticCurveTo(R, base, R - r, base);
            if (bottomTab) { ctx.lineTo(39, base); tabTo(ctx, 13, base); }
            ctx.lineTo(L + r, base); ctx.quadraticCurveTo(L, base, L, base - r);
            ctx.lineTo(L, T + r); ctx.quadraticCurveTo(L, T, L + r, T);
            ctx.closePath();
            return;
        }
        const S = spine, mouths = mouthHeights || [];
        ctx.moveTo(L + r, T);
        ctx.lineTo(13, T); notch(ctx, 13, T);
        ctx.lineTo(R - r, T); ctx.quadraticCurveTo(R, T, R, T + r);
        let y = headHeight;
        ctx.lineTo(R, y - r); ctx.quadraticCurveTo(R, y, R - r, y);
        ctx.lineTo(S + 39, y); tabTo(ctx, S + 13, y); ctx.lineTo(S, y);
        for (let k = 0; k < mouths.length; ++k) {
            const foot = k === mouths.length - 1;
            y += mouths[k];
            ctx.lineTo(S, y);
            if (!(flatEnds || [])[k]) { ctx.lineTo(S + 13, y); notch(ctx, S + 13, y); }
            ctx.lineTo(R - r, y); ctx.quadraticCurveTo(R, y, R, y + r);
            y += foot ? footHeight - ins : midHeight;
            ctx.lineTo(R, y - r); ctx.quadraticCurveTo(R, y, R - r, y);
            if (foot) {
                ctx.lineTo(39, y); tabTo(ctx, 13, y);
                ctx.lineTo(L + r, y); ctx.quadraticCurveTo(L, y, L, y - r);
            } else {
                ctx.lineTo(S + 39, y); tabTo(ctx, S + 13, y); ctx.lineTo(S, y);
            }
        }
        ctx.lineTo(L, T + r); ctx.quadraticCurveTo(L, T, L + r, T);
        ctx.closePath();
    }

    // The outline as SVG path data, traced through a tiny canvas-like writer.
    function writer() {
        const parts = [];
        const n = v => Math.round(v * 100) / 100;
        return {
            moveTo: (x, y) => parts.push("M" + n(x) + " " + n(y)),
            lineTo: (x, y) => parts.push("L" + n(x) + " " + n(y)),
            quadraticCurveTo: (cx, cy, x, y) => parts.push("Q" + n(cx) + " " + n(cy) + " " + n(x) + " " + n(y)),
            closePath: () => parts.push("Z"),
            text: () => parts.join(" ")
        };
    }
    readonly property string outlinePath: {
        if (width <= 0 || height <= 0) return "";
        const w = writer();
        trace(w);
        return w.text();
    }

    ShapePath {
        strokeColor: root.hovered ? root.hoverColor : root.outline
        strokeWidth: 1.3
        joinStyle: ShapePath.RoundJoin
        fillGradient: LinearGradient {
            x1: 0; y1: 0; x2: root.width; y2: root.height
            GradientStop { position: 0; color: Qt.lighter(root.fill, 1.11) }
            GradientStop { position: 1; color: root.fill }
        }
        PathSvg { path: root.outlinePath }
    }
}
