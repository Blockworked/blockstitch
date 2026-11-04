import QtQuick

// Holds every Flickable above a text field still while a mouse press in it
// lasts, so dragging selects text instead of panning the view. Text inputs
// only keep the grab once a drag goes sideways, so a vertical one was stolen.
PointHandler {
    id: hold
    property Item field: parent
    target: null
    acceptedButtons: Qt.LeftButton
    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad | PointerDevice.Stylus
    enabled: !!field && !field.readOnly && field.selectByMouse
    property var held: []
    onActiveChanged: active ? grab() : release()
    Component.onDestruction: release()
    // A Flickable whose `interactive` is a binding offers `textHolds` to
    // count against instead; the rest are switched off and back on.
    function grab() {
        release();
        const list = [];
        for (let p = field.parent; p; p = p.parent) {
            if (p.textHolds !== undefined) { p.textHolds++; list.push(p); }
            else if (p instanceof Flickable && p.interactive) { p.interactive = false; list.push(p); }
        }
        held = list;
    }
    function release() {
        for (const p of held) {
            if (!p) continue;
            if (p.textHolds !== undefined) p.textHolds = Math.max(0, p.textHolds - 1);
            else p.interactive = true;
        }
        held = [];
    }
}
