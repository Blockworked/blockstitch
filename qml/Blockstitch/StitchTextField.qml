import QtQuick
import QtQuick.Templates as T

// Built on the template rather than the Basic style's TextField: its always
// present placeholder makes Qt revisit every field each time the canvas
// scrolls or its origin moves. This placeholder exists only while it shows.
T.TextField {
    id:control
    implicitWidth:implicitBackgroundWidth + leftInset + rightInset
        || Math.max(contentWidth, placeholderLoader.item ? placeholderLoader.item.implicitWidth : 0) + leftPadding + rightPadding
    implicitHeight:Math.max(34,Theme.minimumTarget)
    color:Theme.text; placeholderTextColor:Theme.textDim; selectionColor:Theme.accent; selectedTextColor:"white"
    font.pixelSize:13; selectByMouse:true; verticalAlignment:TextInput.AlignVCenter
    leftPadding:10;rightPadding:10;topPadding:5;bottomPadding:5

    TextSelectHold {}

    Loader {
        id:placeholderLoader
        active:control.placeholderText.length > 0 && !control.length && !control.preeditText
            && (!control.activeFocus || control.horizontalAlignment !== Qt.AlignHCenter)
        x:control.leftPadding; y:control.topPadding
        width:control.width - (control.leftPadding + control.rightPadding)
        height:control.height - (control.topPadding + control.bottomPadding)
        sourceComponent:Text {
            text:control.placeholderText
            font:control.font
            color:control.placeholderTextColor
            verticalAlignment:control.verticalAlignment
            horizontalAlignment:control.horizontalAlignment
            elide:Text.ElideRight
            renderType:control.renderType
        }
    }

    background:Rectangle {
        radius:5;color:control.enabled?Theme.field:Theme.canvas
        border.color:control.activeFocus?Theme.accent:Theme.border
        border.width:control.activeFocus?1.5:1
        Behavior on border.color { enabled:Motion.enabled; ColorAnimation { duration:Motion.quick } }
    }
}
