import QtQuick
import QtQuick.Controls

TextField {
    id:control
    color:Theme.text; placeholderTextColor:Theme.textDim; selectionColor:Theme.accent
    font.pixelSize:13; selectByMouse:true; implicitHeight:34
    leftPadding:10;rightPadding:10;topPadding:5;bottomPadding:5
    background:Rectangle {
        radius:5;color:control.enabled?Theme.field:"#27282a"
        border.color:control.activeFocus?Theme.accent:Theme.border
        border.width:control.activeFocus?1.5:1
    }
}
