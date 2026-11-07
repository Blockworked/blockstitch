import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// A vertically scrolling form with fixed header and footer slots.
Page {
    id: control
    default property alias content: body.data
    property string description: ""
    property alias contentSpacing: body.spacing
    readonly property alias scrollView: scroll
    padding: 22

    function revealFocus() {
        const item = Window.window ? Window.window.activeFocusItem : null;
        let ancestor = item;
        while (ancestor && ancestor !== body) ancestor = ancestor.parent;
        if (!ancestor || !item) return;
        const f = scroll.contentItem;
        const point = item.mapToItem(f.contentItem, 0, 0);
        const bottom = point.y + Math.min(item.height, f.height);
        let y = f.contentY;
        if (point.y < y) y = point.y;
        else if (bottom > y + f.height) y = bottom - f.height;
        if (y !== f.contentY) scroll.wheelHandler.smooth.scrollTo(NaN, y, false);
    }
    onAvailableHeightChanged: Qt.callLater(revealFocus)
    Connections {
        target: control.Window.window
        function onActiveFocusItemChanged() { Qt.callLater(control.revealFocus); }
    }

    header: ColumnLayout {
        spacing: 6
        visible: control.title.length > 0 || control.description.length > 0
        Text {
            visible: control.title.length > 0
            Layout.fillWidth: true
            Layout.leftMargin: control.leftPadding; Layout.rightMargin: control.rightPadding
            Layout.topMargin: control.topPadding
            text: control.title; textFormat: Text.PlainText
            color: Theme.text; font.pixelSize: 22; font.weight: Font.Bold
            wrapMode: Text.WordWrap
        }
        Text {
            visible: control.description.length > 0
            Layout.fillWidth: true
            Layout.leftMargin: control.leftPadding; Layout.rightMargin: control.rightPadding
            Layout.topMargin: control.title.length ? 0 : control.topPadding
            text: control.description; textFormat: Text.PlainText
            color: Theme.textDim; font.pixelSize: 12
            wrapMode: Text.WordWrap
        }
    }
    background: Rectangle { color: Theme.window }
    contentItem: StitchScrollView {
        id: scroll
        implicitWidth: 360
        implicitHeight: body.implicitHeight
        contentWidth: availableWidth
        contentHeight: body.implicitHeight
        ColumnLayout {
            id: body
            width: scroll.availableWidth
            spacing: 12
        }
    }
}
