import QtQuick

// Smooth wheel/touchpad scrolling for a ScrollView or ListView; declare it as a child and set flickable.
WheelHandler {
    id: handler
    // the ScrollView's contentItem, e.g. flickable: myScroll.contentItem
    property var flickable: null
    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
    orientation: Qt.Horizontal | Qt.Vertical
    target: null

    // See SmoothScroll.isTouchpad: a scroll phase or a touchpad device, never pixelDelta,
    // which mouse wheels send too on Wayland and with libinput on X11.
    function isTouchpad(event) { return smooth.isTouchpad(event); }

    // A list's touchpad pan starts gentler than the canvas's (3 px per unit, not 6).
    function pan(ad, pd, touchpad) { return smooth.wheelStep(ad, pd, touchpad, 3); }

    // Flickable must not also handle the wheel or it overrides this
    readonly property Binding interactionOverride: Binding {
        target: handler.flickable
        property: "interactive"
        value: false
        when: handler.active && handler.flickable !== null
        restoreMode: Binding.RestoreBindingOrValue
    }

    onWheel: event => {
        const f = flickable;
        if (!f) return;
        // A wheel notch glides to its target; touchpad pans already arrive smooth.
        const tp = isTouchpad(event);
        smooth.scrollBy(pan(event.angleDelta.x, event.pixelDelta.x, tp), pan(event.angleDelta.y, event.pixelDelta.y, tp), !tp);
        event.accepted = true;
    }

    property SmoothScroll smooth: SmoothScroll { flickable: handler.flickable }
}
