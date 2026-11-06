import QtQuick
import QtQuick.Controls

// The palette's block list for one category ("" = every category), built
// from the panel's sections. PalettePanel hosts one per open accordion
// section, or one for the whole list.
Column {
    id: blk
    // The PalettePanel this list belongs to.
    required property Item panel
    // A section's name: sentence case after a small block notch, so it reads as
    // part of the palette rather than as a caption.
    component SectionLabel: Text {
        color: Theme.textDim
        font.pixelSize: 13
        font.weight: Font.DemiBold
    }
    property string only: ""
    spacing: 8
    function itemShown(c, label) {
        return panel.searching ? panel.matches(label) : (only === "" || only === c);
    }
    function sectionShown(c) {
        return !panel.searching && (only === "" || only === c);
    }
    Repeater {
        model: panel.resolvedSections
        delegate: Column {
            id: sec
            required property var modelData
            required property int index
            readonly property bool firstOfCategory: index === 0 || panel.resolvedSections[index - 1].category !== modelData.category
            visible: panel.searching ? modelData.items.some(i => panel.itemMatches(i)) : (blk.only === "" || blk.only === modelData.category)
            spacing: 8
            Text {
                visible: blk.only === "" && !panel.searching && sec.firstOfCategory
                text: panel.categoryName(sec.modelData.category)
                color: Theme.text
                font.pixelSize: 15
                font.weight: Font.Bold
                topPadding: sec.index === 0 ? 0 : 12
            }
            Row {
                visible: !panel.searching && (sec.modelData.title !== "" || sec.modelData.action !== "")
                spacing: 8
                topPadding: 4
                SectionLabel {
                    visible: sec.modelData.title !== ""
                    text: sec.modelData.title
                    anchors.verticalCenter: parent.verticalCenter
                }
                BwButton {
                    visible: sec.modelData.action !== ""
                    text: panel.actionText(sec.modelData.action, sec.modelData.actionText)
                    implicitHeight: 28
                    font.pixelSize: 11
                    onClicked: panel.sectionAction(sec.modelData.action)
                }
            }
            Repeater {
                model: sec.modelData.items
                delegate: Loader {
                    id: entry
                    required property var modelData
                    // Past the first sections, blocks build over the next
                    // frames instead of all before the palette first shows.
                    asynchronous: sec.index > 1
                    property bool pending: false
                    Component.onCompleted: if (status === Loader.Loading) {
                        pending = true;
                        ++panel.pendingEntries;
                    }
                    onStatusChanged: if (pending && status !== Loader.Loading) {
                        pending = false;
                        --panel.pendingEntries;
                    }
                    Component.onDestruction: if (pending)
                        --panel.pendingEntries
                    visible: !panel.searching || panel.itemMatches(modelData)
                    sourceComponent: modelData.kind === "instruction" ? instructionEntry : modelData.kind === "operator" ? operatorEntry : modelData.kind === "variables" ? variablesEntry : modelData.kind === "lists" ? listsEntry : dictsEntry
                    Component {
                        id: instructionEntry
                        PaletteBlock {
                            instruction: panel.prefab(entry.modelData.name)
                            spec: ({
                                    kind: "instruction",
                                    type: entry.modelData.name,
                                    instruction: instruction
                                })
                            variables: Array.from(panel.variables || [])
                            lists: Array.from(panel.lists || [])
                            blockDefinitions: panel.blockDefinitions
                            keyCapture: panel.keyCapture
                            onDragStarted: (sp, sx, sy, ox, oy) => panel.dragStarted(sp, sx, sy, ox, oy)
                            onDragMoved: (sx, sy) => panel.dragMoved(sx, sy)
                            onDragEnded: (sx, sy) => panel.dragEnded(sx, sy)
                            onDragCanceled: panel.dragCanceled()
                            onActivated: panel.blockActivated(entry.modelData.name, instruction)
                            onKeyCaptureRequested: panel.standaloneKeyCaptureRequested()
                            onPieceActionRequested: (action, instruction) => panel.pieceActionRequested(action, instruction)
                            onDetailsRequested: type => panel.detailsRequested(type, type, qsTr("See what this block does and where it can be used."))
                        }
                    }
                    Component {
                        id: operatorEntry
                        PaletteValue {
                            valueData: panel.operatorValue(entry.modelData.spec)
                            spec: ({
                                    kind: "value",
                                    value: valueData
                                })
                            blockDefinitions: panel.blockDefinitions
                            onDragStarted: (sp, sx, sy, ox, oy) => panel.dragStarted(sp, sx, sy, ox, oy)
                            onDragMoved: (sx, sy) => panel.dragMoved(sx, sy)
                            onDragEnded: (sx, sy) => panel.dragEnded(sx, sy)
                            onDragCanceled: panel.dragCanceled()
                            onActivated: panel.valueActivated(valueData)
                            onDetailsRequested: kind => panel.detailsRequested(kind, kind, panel.operatorExplainer(kind))
                        }
                    }
                    Component {
                        id: variablesEntry
                        Column {
                            spacing: 8
                            Repeater {
                                model: panel.variables || []
                                delegate: PaletteValue {
                                    required property string modelData
                                    visible: !panel.searching || panel.matches(modelData)
                                    valueData: ({
                                            kind: "Var",
                                            name: modelData
                                        })
                                    editable: false
                                    spec: ({
                                            kind: "value",
                                            value: valueData
                                        })
                                    blockDefinitions: panel.blockDefinitions
                                    extraMenu: (panel.offerSetVariableValue ? [
                                            {
                                                id: "set",
                                                text: qsTr("Set value"),
                                                icon: "pencil"
                                            }
                                        ] : []).concat([
                                        {
                                            id: "rename",
                                            text: qsTr("Rename variable"),
                                            icon: "equal"
                                        },
                                        {
                                            id: "delete",
                                            text: qsTr("Delete variable"),
                                            icon: "trash",
                                            danger: true
                                        }
                                    ])
                                    onExtraMenuTriggered: id => id === "set" ? panel.setVariableValueRequested(modelData) : id === "rename" ? panel.renameVariableRequested(modelData) : panel.deleteVariableRequested(modelData)
                                    onDragStarted: (sp, sx, sy, ox, oy) => panel.dragStarted(sp, sx, sy, ox, oy)
                                    onDragMoved: (sx, sy) => panel.dragMoved(sx, sy)
                                    onDragEnded: (sx, sy) => panel.dragEnded(sx, sy)
                                    onDragCanceled: panel.dragCanceled()
                                    onActivated: panel.valueActivated(valueData)
                                }
                            }
                        }
                    }
                    Component {
                        id: listsEntry
                        CollectionPanel {
                            collections: panel.lists
                            noun: "list"
                            rowWidth: Math.max(230, panel.width - 28 - panel.railWidth - 1)
                            onEditorStateRequested: (name, visible, x, y) => panel.listEditorStateRequested(name, visible, x, y)
                            onRenameRequested: name => panel.renameListRequested(name)
                            onDeleteRequested: name => panel.deleteListRequested(name)
                            onDetailsRequested: name => panel.detailsRequested(name, "List", qsTr("A document-wide ordered collection of text and number items."))
                        }
                    }
                    Component {
                        id: dictsEntry
                        CollectionPanel {
                            collections: panel.dicts
                            noun: "dict"
                            rowWidth: Math.max(230, panel.width - 28 - panel.railWidth - 1)
                            emptyText: qsTr("Make a dict, then check it to open its editor on the canvas.")
                            onEditorStateRequested: (name, visible, x, y) => panel.dictEditorStateRequested(name, visible, x, y)
                            onRenameRequested: name => panel.renameDictRequested(name)
                            onDeleteRequested: name => panel.deleteDictRequested(name)
                            onDetailsRequested: name => panel.detailsRequested(name, "Dict", qsTr("A document-wide collection of text and number values, looked up by key."))
                        }
                    }
                }
            }
        }
    }
    Row {
        visible: blk.sectionShown("custom")
        spacing: 8
        topPadding: 8
        SectionLabel {
            text: qsTr("My blocks")
            anchors.verticalCenter: parent.verticalCenter
        }
        BwButton {
            text: qsTr("Make a Block")
            implicitHeight: 28
            font.pixelSize: 11
            onClicked: panel.makeBlockRequested()
        }
    }
    Repeater {
        model: (panel.blockDefinitions || []).filter(def => !def.read_only)
        delegate: Loader {
            id: customItem
            required property var modelData
            visible: blk.itemShown("custom", panel.customLabel(modelData))
            sourceComponent: panel.isReporter(modelData) ? customReporter : customCall
            Component {
                id: customCall
                PaletteBlock {
                    instruction: panel.customInstruction(customItem.modelData)
                    spec: ({
                            kind: "custom",
                            definition: customItem.modelData,
                            instruction: instruction,
                            color: blockColor
                        })
                    variables: Array.from(panel.variables || [])
                    lists: Array.from(panel.lists || [])
                    blockDefinitions: panel.blockDefinitions
                    keyCapture: panel.keyCapture
                    blockColor: customItem.modelData.color || Theme.block
                    onDragStarted: (sp, sx, sy, ox, oy) => panel.dragStarted(sp, sx, sy, ox, oy)
                    onDragMoved: (sx, sy) => panel.dragMoved(sx, sy)
                    onDragEnded: (sx, sy) => panel.dragEnded(sx, sy)
                    onDragCanceled: panel.dragCanceled()
                    onActivated: panel.customBlockActivated(customItem.modelData)
                    onDetailsRequested: panel.detailsRequested(panel.customLabel(customItem.modelData), customItem.modelData.id, panel.customBlockDetails)
                    extraMenu: panel.customMenu
                    onExtraMenuTriggered: id => panel.customMenuAction(id, customItem.modelData)
                }
            }
            Component {
                id: customReporter
                PaletteValue {
                    valueData: panel.customValue(customItem.modelData)
                    editable: false
                    forceBoolean: customItem.modelData.shape === "ReturnsBool"
                    callLabel: panel.customLabel(customItem.modelData)
                    blockDefinitions: panel.blockDefinitions
                    spec: ({
                            kind: "value",
                            value: valueData,
                            forceBoolean: forceBoolean,
                            label: callLabel
                        })
                    onDragStarted: (sp, sx, sy, ox, oy) => panel.dragStarted(sp, sx, sy, ox, oy)
                    onDragMoved: (sx, sy) => panel.dragMoved(sx, sy)
                    onDragEnded: (sx, sy) => panel.dragEnded(sx, sy)
                    onDragCanceled: panel.dragCanceled()
                    onActivated: panel.valueActivated(valueData)
                    onDetailsRequested: panel.detailsRequested(panel.customLabel(customItem.modelData), customItem.modelData.id, panel.customReporterDetails)
                    extraMenu: panel.customMenu
                    onExtraMenuTriggered: id => panel.customMenuAction(id, customItem.modelData)
                }
            }
        }
    }
    Row {
        visible: panel.blockLibraryEnabled && blk.sectionShown("community")
        spacing: 8
        topPadding: 8
        SectionLabel {
            text: qsTr("Community blocks")
            anchors.verticalCenter: parent.verticalCenter
        }
        BwButton {
            text: qsTr("Browse")
            iconName: "book-open"
            implicitHeight: 28
            font.pixelSize: 11
            onClicked: panel.browseBlocksRequested()
        }
    }
    Repeater {
        model: panel.communityPacks
        delegate: Column {
            id: packSection
            required property var modelData
            readonly property bool matchesPack: panel.searching && panel.matches(modelData.name)
            visible: modelData.blocks.some(def => matchesPack || blk.itemShown("community", panel.customLabel(def)))
            spacing: 8
            topPadding: 6
            Text {
                id: packHeading
                objectName: "communityPackHeading"
                width: panel.contentWidth
                text: packSection.modelData.name
                color: Theme.textDim
                font.pixelSize: 12
                font.weight: Font.DemiBold
                elide: Text.ElideRight
                ToolTip.visible: headingHover.hovered && truncated
                ToolTip.text: text
                HoverHandler {
                    id: headingHover
                }
            }
            Repeater {
                model: packSection.modelData.blocks
                delegate: Loader {
                    id: communityItem
                    required property var modelData
                    visible: packSection.matchesPack || blk.itemShown("community", panel.customLabel(modelData))
                    sourceComponent: panel.isReporter(modelData) ? communityReporter : communityCall
                    Component {
                        id: communityCall
                        PaletteBlock {
                            instruction: panel.customInstruction(communityItem.modelData)
                            spec: ({
                                    kind: "custom",
                                    definition: communityItem.modelData,
                                    instruction: instruction,
                                    color: blockColor
                                })
                            variables: Array.from(panel.variables || [])
                            lists: Array.from(panel.lists || [])
                            blockDefinitions: panel.blockDefinitions
                            keyCapture: panel.keyCapture
                            blockColor: communityItem.modelData.color || Theme.block
                            onDragStarted: (sp, sx, sy, ox, oy) => panel.dragStarted(sp, sx, sy, ox, oy)
                            onDragMoved: (sx, sy) => panel.dragMoved(sx, sy)
                            onDragEnded: (sx, sy) => panel.dragEnded(sx, sy)
                            onDragCanceled: panel.dragCanceled()
                            onActivated: panel.customBlockActivated(communityItem.modelData)
                            onDetailsRequested: panel.detailsRequested(panel.customLabel(communityItem.modelData), communityItem.modelData.id, panel.customBlockDetails)
                            extraMenu: [
                                {
                                    id: "details",
                                    text: qsTr("Details"),
                                    icon: "info"
                                }
                            ]
                            onExtraMenuTriggered: id => panel.customMenuAction(id, communityItem.modelData)
                        }
                    }
                    Component {
                        id: communityReporter
                        PaletteValue {
                            valueData: panel.customValue(communityItem.modelData)
                            editable: false
                            forceBoolean: communityItem.modelData.shape === "ReturnsBool"
                            callLabel: panel.customLabel(communityItem.modelData)
                            blockDefinitions: panel.blockDefinitions
                            spec: ({
                                    kind: "value",
                                    value: valueData,
                                    forceBoolean: forceBoolean,
                                    label: callLabel
                                })
                            onDragStarted: (sp, sx, sy, ox, oy) => panel.dragStarted(sp, sx, sy, ox, oy)
                            onDragMoved: (sx, sy) => panel.dragMoved(sx, sy)
                            onDragEnded: (sx, sy) => panel.dragEnded(sx, sy)
                            onDragCanceled: panel.dragCanceled()
                            onActivated: panel.valueActivated(valueData)
                            onDetailsRequested: panel.detailsRequested(panel.customLabel(communityItem.modelData), communityItem.modelData.id, panel.customReporterDetails)
                            extraMenu: [
                                {
                                    id: "details",
                                    text: qsTr("Details"),
                                    icon: "info"
                                }
                            ]
                            onExtraMenuTriggered: id => panel.customMenuAction(id, communityItem.modelData)
                        }
                    }
                }
            }
        }
    }
    Text {
        visible: panel.noResults
        text: qsTr("No blocks match \"%1\"").arg(panel.searchText.trim())
        color: Theme.textDim
        font.pixelSize: 12
        topPadding: 8
    }
}
