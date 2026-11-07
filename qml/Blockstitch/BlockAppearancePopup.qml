import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// The Appearance popup of BlockDefinitionEditor: color presets, the custom
// color picker and the icon button, all written to the editor's fields.
Popup {
    id: appearancePopup
    objectName: "appearancePopup"
    required property Item editor
    parent: Overlay.overlay
    anchors.centerIn: parent
    width: Math.min(500, parent.width - 32)
    padding: 20
    modal: true
    focus: true
    background: Rectangle { color: Theme.panel; radius: Theme.radius; border.color: Theme.border }
    contentItem: ColumnLayout {
        spacing: 16
        Label { text: qsTr("Appearance"); color: Theme.text; font.pixelSize: 18; font.bold: true }
        Grid {
            Layout.alignment: Qt.AlignHCenter
            columns: 12
            spacing: 7
            Repeater {
                model: editor.colorPresets
                delegate: Rectangle {
                    required property string modelData
                    width: 30
                    height: 30
                    radius: 15
                    color: modelData
                    border.width: editor.blockColor === modelData ? 3 : 1
                    border.color: editor.blockColor === modelData ? Theme.text : Theme.border
                    HoverHandler {
                        cursorShape: Qt.PointingHandCursor
                    }
                    TapHandler {
                        onTapped: {
                            editor.blockColor = modelData;
                            editor.customPickerOpen = false;
                        }
                    }
                }
            }
            Rectangle {
                visible: editor.allowCustomColor
                width: 30
                height: 30
                radius: 15
                color: "#ff6680"
                border.width: editor.customPickerOpen || editor.colorPresets.indexOf(editor.blockColor) < 0 ? 3 : 1
                border.color: editor.customPickerOpen || editor.colorPresets.indexOf(editor.blockColor) < 0 ? Theme.text : Theme.border
                LucideIcon {
                    anchors.centerIn: parent
                    width: 15
                    height: 15
                    name: "pipette"
                    color: Theme.text
                }
                HoverHandler {
                    cursorShape: Qt.PointingHandCursor
                }
                TapHandler {
                    onTapped: editor.toggleCustomPicker()
                }
            }
        }

        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: 10
            Text {
                text: qsTr("Icon")
                color: Theme.textDim
                font.pixelSize: 12
                Layout.alignment: Qt.AlignVCenter
            }
            StitchButton {
                text: editor.blockIcon ? editor.blockIcon : qsTr("Default")
                iconName: editor.blockIcon || "blocks"
                implicitHeight: 32
                onClicked: {
                    editor.iconSearch = "";
                    editor.openIconPicker();
                    iconGrid.positionViewAtBeginning();
                    iconSearchField.forceActiveFocus();
                }
            }
            StitchButton {
                visible: editor.blockIcon.length > 0
                text: qsTr("Reset")
                implicitHeight: 32
                onClicked: editor.blockIcon = ""
            }
        }

        Rectangle {
            id: picker
            visible: editor.customPickerOpen
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: 430
            Layout.preferredHeight: 196
            radius: Theme.radius
            color: Theme.panelRaised
            border.color: Theme.border
            readonly property color pure: Qt.hsva(editor.customHue / 360, 1, 1, 1)

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 12
                spacing: 10

                // Saturation across, value down: the usual picker square.
                Rectangle {
                    id: field
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: 4
                    clip: true
                    border.color: Theme.border
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0; color: "#ffffff" }
                        GradientStop { position: 1; color: picker.pure }
                    }
                    Rectangle {
                        anchors.fill: parent
                        gradient: Gradient {
                            GradientStop { position: 0; color: "#00000000" }
                            GradientStop { position: 1; color: "#ff000000" }
                        }
                    }
                    Rectangle {
                        x: editor.customSaturation * field.width - width / 2
                        y: (1 - editor.customValue) * field.height - height / 2
                        width: 14
                        height: 14
                        radius: 7
                        color: "transparent"
                        border.width: 2
                        border.color: editor.customValue > 0.6 && editor.customSaturation < 0.5 ? "#000000" : "#ffffff"
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.CrossCursor
                        preventStealing: true
                        function pick(mouse) {
                            editor.customSaturation = Math.max(0, Math.min(1, mouse.x / width));
                            editor.customValue = 1 - Math.max(0, Math.min(1, mouse.y / height));
                            editor.updateCustomColor();
                        }
                        onPressed: mouse => pick(mouse)
                        onPositionChanged: mouse => { if (pressed) pick(mouse); }
                    }
                }

                Rectangle {
                    id: hueStrip
                    Layout.fillWidth: true
                    Layout.preferredHeight: 14
                    radius: 7
                    border.color: Theme.border
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0 / 6; color: "#ff0000" }
                        GradientStop { position: 1 / 6; color: "#ffff00" }
                        GradientStop { position: 2 / 6; color: "#00ff00" }
                        GradientStop { position: 3 / 6; color: "#00ffff" }
                        GradientStop { position: 4 / 6; color: "#0000ff" }
                        GradientStop { position: 5 / 6; color: "#ff00ff" }
                        GradientStop { position: 6 / 6; color: "#ff0000" }
                    }
                    Rectangle {
                        x: editor.customHue / 360 * (hueStrip.width - width)
                        y: -2
                        width: 10
                        height: parent.height + 4
                        radius: 5
                        color: picker.pure
                        border.width: 2
                        border.color: "#ffffff"
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        preventStealing: true
                        function pick(mouse) {
                            editor.customHue = Math.max(0, Math.min(359.99, mouse.x / width * 360));
                            editor.updateCustomColor();
                        }
                        onPressed: mouse => pick(mouse)
                        onPositionChanged: mouse => { if (pressed) pick(mouse); }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10
                    Rectangle {
                        Layout.preferredWidth: 28
                        Layout.preferredHeight: 28
                        radius: 14
                        color: editor.blockColor
                        border.color: Theme.border
                    }
                    StitchTextField {
                        id: hexField
                        Layout.preferredWidth: 100
                        font.family: "monospace"
                        text: editor.blockColor
                        onEditingFinished: {
                            const typed = text.trim().toUpperCase();
                            const hex = typed.startsWith("#") ? typed : "#" + typed;
                            if (editor.hexToHsv(hex)) {
                                editor.blockColor = hex;
                                editor.loadCustomColor(hex);
                            }
                            text = Qt.binding(() => editor.blockColor);
                        }
                    }
                    Item {
                        Layout.fillWidth: true
                    }
                    StitchButton {
                        text: qsTr("Done")
                        primary: true
                        implicitWidth: 60
                        onClicked: editor.customPickerOpen = false
                    }
                }
            }
        }

        StitchButton { text: qsTr("Done"); Layout.alignment: Qt.AlignRight; onClicked: appearancePopup.close() }
    }
}
