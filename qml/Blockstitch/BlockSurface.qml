import QtQuick

Canvas {
    id: root
    property string shape: "stack"
    property color fill: Theme.block
    property color outline: Theme.border
    property bool hovered: false
    antialiasing: true
    onWidthChanged: requestPaint(); onHeightChanged: requestPaint()
    onFillChanged: requestPaint(); onOutlineChanged: requestPaint()
    onHoveredChanged: requestPaint(); onShapeChanged: requestPaint()

    function trace(ctx, inset) {
        const w = width, h = height, r = 5 + inset, tab = 8;
        const topNotch = shape !== "header", bottomTab = shape !== "cap";
        const base = bottomTab ? h - tab : h;
        ctx.beginPath(); ctx.moveTo(r, inset);
        if (topNotch) { ctx.lineTo(13, inset); ctx.lineTo(17, inset + 5); ctx.lineTo(21, inset + tab); ctx.lineTo(31, inset + tab); ctx.lineTo(35, inset + 5); ctx.lineTo(39, inset); }
        ctx.lineTo(w-r,inset); ctx.quadraticCurveTo(w-inset,inset,w-inset,r); ctx.lineTo(w-inset,base-r); ctx.quadraticCurveTo(w-inset,base-inset,w-r,base-inset);
        if (bottomTab) { ctx.lineTo(39,h-tab-inset); ctx.lineTo(35,h-tab+5-inset); ctx.lineTo(31,h-inset); ctx.lineTo(21,h-inset); ctx.lineTo(17,h-tab+5-inset); ctx.lineTo(13,h-tab-inset); }
        ctx.lineTo(r,base-inset); ctx.quadraticCurveTo(inset,base-inset,inset,base-r); ctx.lineTo(inset,r); ctx.quadraticCurveTo(inset,inset,r,inset); ctx.closePath();
    }
    onPaint: {
        const ctx=getContext("2d"); ctx.reset(); trace(ctx,.5); ctx.fillStyle=hovered?Theme.accent:outline; ctx.fill(); trace(ctx,1.7);
        const g=ctx.createLinearGradient(0,0,width,height); g.addColorStop(0,Qt.lighter(fill,1.11)); g.addColorStop(1,fill); ctx.fillStyle=g; ctx.fill();
    }
}
