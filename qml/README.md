# Blockstitch QML frontend

The components are registered as the `com.blockworked.Blockstitch` QML module
by the `blockstitch-qml` crate. `BlockCanvas` renders draggable Scratch-style
strands on a zoomable dotted workspace, `PalettePanel` is the sidebar, and the
small controls share one visual language through `Theme`.

Native consumers depend on the repository's root Cargo package and call
`blockstitch_qml::init()` before creating their QML engine. The browser build
of the same QML is the website's WebAssembly demo (see below).

`qml/module.json` is the module's one manifest: its URI and version, every
file, the singletons and the Qt modules it needs. `build.rs` registers the
crate's module from it, and CMake projects (the website's WebAssembly demo)
get the same module from `cmake/BlockstitchQml.cmake`:

```cmake
include(<blockstitch>/cmake/BlockstitchQml.cmake)
blockstitch_add_qml_module(blockstitch)   # static; link blockstitchplugin
```

Both builds fail when `qml/Blockstitch/` holds a `.qml` file the manifest
doesn't list, or the manifest lists one that isn't there, so a new component
is added to `module.json` and nowhere else.

## Files

| File | What it is |
| --- | --- |
| `BlockCanvas.qml` | The workspace: strands, floating values, comments and the list and dict editor cards. The helpers below keep its public functions as one-line forwards. |
| `ListEditorCard.qml`, `DictEditorCard.qml` | A list's or dict's floating editor card on the canvas. |
| `BlockDrag.qml`, `SnapGeometry.qml` | A dragged block or tail: pick-up, attach preview, drop, and where it would snap. |
| `ValueDrag.qml`, `ValueDropTargets.qml` | A dragged reporter and the slot it would drop into. |
| `CanvasState.qml` | One canvas's run and debug marks, comment dots, reveal flash and settling value, handed to its blocks. |
| `DropSettle.qml` | Holds a dropped block or value where it landed until the new document arrives. |
| `CanvasZoom.qml`, `StrandBuilder.qml`, `StrandModel.qml` | The canvas's zoom, building strands near the view first, and the strand list that keeps unchanged strands alive. |
| `StrandView.qml`, `FloatingValue.qml`, `CanvasMenu.qml` | One strand on the canvas, a loose reporter, and the canvas background's right-click menu. |
| `CommentCard.qml` | One comment on the canvas, with its line to the block it is attached to. |
| `InstructionBlock.qml`, `ValueChip.qml`, `BooleanSlot.qml` | One block, one reporter, one boolean slot. |
| `BlockMouth.qml`, `BranchHeaderPreview.qml` | A wrap block's mouth, and a branching definition's header drawn as its call. |
| `EnumLeaf.qml`, `KeycapLeaf.qml`, `PickLeaf.qml`, `TextLeaf.qml`, `SummaryLeaf.qml`, `BoxLeaf.qml` | The editors a reporter's slot uses: dropdown, keycaps, host picker, one-line text, multi-line summary, text box. |
| `BlockPiece.qml`, `BlockMenu.qml` | One piece of a block's row, and a block's right-click menu (built the first time it opens). |
| `PalettePanel.qml`, `PaletteBlockList.qml`, `PaletteDragController.qml` | The sidebar, its list of blocks, and dragging out of it. |
| `PaletteBlock.qml`, `PaletteValue.qml` | One block, and one reporter, in the sidebar. |
| `CollectionPanel.qml`, `NameDialog.qml` | The sidebar's lists and dicts, and the dialog that names or renames one. |
| `InstructionList.qml` | A strand's blocks as a model keyed by id, so an edit rebuilds only the blocks it touched. |
| `BlockSurface.qml`, `BlockDragArea.qml` | A block's painted silhouette, and the press-and-drag area on it. |
| `TextEditorDialog.qml` | The bigger editor for a text slot with line breaks. |
| `LucideIcon.qml` | One Lucide icon by name, drawn from `Icons.qml`. |
| `SmoothScroll.qml`, `WheelPan.qml`, `TextSelectHold.qml` | Wheel scrolling that glides, and holding a view still while text is selected. |
| `BlockRegistry.qml` | The host's vocabulary: rows, operators, prefabs, icons, descriptors. |
| `BlockDefinitionEditor.qml` | "Make a Block". |
| `DefinitionPrototype.qml`, `DefinitionPiece.qml` | The definition editor's preview, and one piece in it. |
| `BlockAppearancePopup.qml`, `BlockIconPopup.qml`, `BlockInputsPopup.qml` | Its color and icon pickers, and the Inputs dialog (starting values, multi-line boxes). |
| `Theme.qml`, `Motion.qml`, `Icons.qml` | Colors and sizes, animation timing, Lucide icon paths. |
| `Stitch*.qml` | The small controls (button, check box, combo box, dialog, menu, slider, switch, text field) every host uses for its own UI too. |
| `StitchScrollView.qml`, `StitchListView.qml` | Scroll areas with shared wheel handling. |
| `StitchPage.qml`, `StitchScreenDialog.qml` | Scrolling forms with fixed headings and actions. |

## Registering an app's blocks

`BlockRegistry` holds an app's block vocabulary. An app describes
each instruction type once as a row of pieces and hands them over, and both
`BlockCanvas` and `PalettePanel` draw from it:

```qml
BlockRegistry.registerRows({
    Say: { icon: "message-square", head: [{ kind: "label", text: "say" }, { kind: "value", field: "SayText", key: "text" }] },
    Forever: { icon: "infinity", head: [{ kind: "label", text: "forever" }], mouths: ["body"] },
    WhenStarted: { shape: "header", head: [{ kind: "label", text: "when the project starts" }] }
});
BlockRegistry.registerOperators({ MyReporter: { prefix: "my reporter", result: "number" } });
BlockRegistry.registerPrefabs({ Say: () => ({ text: { kind: "Text", value: "Hello" } }) });
```

Blockstitch draws its own control and data blocks: the variable and list
blocks, `Return` and the loop exits have rows in `BlockRegistry.defaultRows`,
and `If`, `IfElse`, `Repeat`, `Forever` and `While` are drawn by
`InstructionBlock` itself (`BlockRegistry.controlBlocks` lists them with
their bodies; `selfDrawnTypes` adds the custom block types). A
host registers a row for every other type; one without a row draws as its
icon alone. A value piece's `unit` frames the slot with a caption (`"ms"`),
and `keyCapture: true` turns a click on its text into `keyCaptureRequested`
so the host can record a key. While it does, set `BlockCanvas.keyCapture` (and
the palette's) to `{kind: "Strand", strand_id, index}` (the block's path) or
`{kind: "Standalone"}` for a palette block, and the slot shows it is waiting.
`shape`
(`"header"`/`"cap"`) and `mouths` (the instruction keys holding nested
bodies) decide a block's outline; the comments in `BlockRegistry.qml` list
every piece kind. For an instruction-dependent ending, `shape` may be a
function of the instruction returning `"cap"` or `"stack"`.
`blockMenu`/`canvasMenu` add app-specific context menu
items, which come back through `blockMenuAction`/`canvasMenuAction`. An
operator's `enumArg` may give its choices as an array, a function, or
`"lists"`/`"dicts"` for the collection names the canvas was given. Its
`pickArg: {index, action, icon}` puts a button after that arg while it holds
text; a click calls `BlockRegistry.pickHandler(action, location, value)` with
the slot's location, so the host can open a picker and write the choice back
like a typed edit.

A row's `components` keep a block short: each is an optional group of pieces
the user adds from the "+" at the end of the row (or the block's right-click
menu) and takes off with its "x". A component is on while the instruction
holds its `key`, so the host stores it as an optional field:

```qml
FindImage: { head: [{ kind: "label", text: "find" }, picture],
    components: [{ key: "region", label: "search region", icon: "square-dashed", fresh: "",
                   pieces: [{ kind: "label", text: "in region" }, { kind: "text", key: "region" }] }] }
```

A piece inside one may name a field of an object `key` holds with a string
`index`. Components follow the head, or stand where it has a
`{kind: "components"}` piece. The palette shows a block without the "+".

Any text slot can hold several lines. A one-line field opens a bigger editor
(`TextEditorDialog`) from its expand button or Shift+Enter, and text that
already has line breaks shows its first line with a "+N lines" badge. A value
piece with `box: true` instead gets a line of its own under a statement's row,
a text box showing every line (`boxLabel` captions it, `monospace` is for
code); wraps and hats keep it in the row. A custom block input with
`multiline` set is drawn the same way at its calls.

### Operator descriptors

What a fresh operator holds comes from `blockstitch-core`, not the QML.
`value::operator_descriptors()` describes every palette operator: its `kind`,
wire `op`, `arity`, `result` (`number`/`text`/`bool`, none for a host one) and
per slot a `type`, a `default` value, and where known the fixed `choices`, a
list/dict `names` source and `one_based`. `BlockRegistry` carries the
built-ins as a generated table (`blockstitch-core/tests/descriptors.rs`
checks it; `BLESS=1` rewrites it), and a host hands over its registered
operators the same way:

```qml
BlockRegistry.registerDescriptors(hostDescriptors)   // host_operator_descriptors() as JSON
const value = BlockRegistry.freshValue("LetterOf")   // {kind:"Op", op:"LetterOf", args:[1, ""], ...}
```

`freshValue(kind, names)` fills an empty list/dict slot with the first name
and an empty dropdown slot with its first choice; everything else is the
core's default. Labels, layouts and dropdown choices stay in
`registerOperators`.

### What a neutral host gets

Nothing host-specific: no marked-strand badge (`strandMark` is empty), no
rows or icons beyond the shared control and data blocks, and no palette
prefabs for host blocks. A host turns its features on and registers
the rest (`registerRows`, `registerPrefabs`, `registerIcons({MoveMouse: "move"})`).

A row whose pieces depend on the instruction (one generic type that many
app-defined blocks share) gives `head` as a function of the instruction, and
a piece (value, dropdown or text) may carry `index` to read and write one entry
of an array held under its `key` instead of the key itself.

The same goes for an operator many app-defined reporters share: `layout` is an
array (or a function of the value) of `{label, arg: -1}` and `{arg, bool}` pieces, and
the args it does not name are not drawn, so a generic `Ext(name, ...slots)`
reporter can show only its label and slots. `result` may likewise be a
function of the value, so such a reporter takes the boolean shape when its
block answers true or false.

## Dicts

`BlockCanvas.dicts` and `PalettePanel.dicts` take the document's dicts
(`{name, entries: [{key, value}], editor_visible, editor_x, editor_y}`).
Visible ones get an editor card on the canvas that reports edits through
`dictEntriesEdited`/`dictEditorStateChanged`, and the palette lists them in a
`CollectionPanel` beside the lists with their reporters (`DictValue`,
`DictHasKey`, `DictSize`, `DictKeys`, `DictAsJson`, `DictIsEmpty`).

## Custom block definitions

`BlockDefinitionEditor` is the "Make a Block" surface every host shares:
labels, inputs and branches with stable piece ids, shape, color, icon,
identifier, description and input defaults, with a live preview. Put it in
the host's own dialog, call `load(def)` or `reset()` when it opens (then
`focusFirst()`), and send what it emits:

```qml
BlockDefinitionEditor {
    allowBranches: false            // what the host's runtime can run
    onCreateRequested: draft => app.invoke("create_block", draft, close, e => fail(e))
    onEditRequested: (id, draft) => app.invoke("edit_block", Object.assign({ blockId: id }, draft), close, e => fail(e))
    onCancelled: close()
}
```

A draft is `{pieces, shape, color, icon, identifier, description}`. A piece
keeps every key it was loaded with, and a host without `allowDefaults` passes
stored defaults through untouched, so nothing a definition holds is dropped.
Branches a definition already has stay editable when `allowBranches` is off.
`shapes`, `allowCustomColor` and `colorPresets` narrow the rest; `textMenu`,
`detailsTitle`, `detailsNote` and `detailsPanel` are host hooks. The backend
stays the authority: `BlockDef::validate_pieces` checks the pieces and
`update_block` moves call-site arguments and branch bodies by piece id.

## Scrolling and screens

`StitchScrollView` and `StitchListView` are drop-in Qt Quick Controls `ScrollView`
and Qt Quick `ListView` variants with clipping and smooth wheel scrolling
already installed. `StitchListView` also supplies a vertical scrollbar. They
keep the underlying controls' sizing, models, delegates and keyboard APIs.
Use ordinary `contentWidth: availableWidth` for a vertically scrolling
`StitchScrollView`; leave it unset when content should scroll horizontally too.

```qml
StitchScrollView {
    anchors.fill: parent
    contentWidth: availableWidth
    Column {
        width: parent.width
        // Content...
    }
}
StitchListView {
    model: entries
    delegate: Text { required property string modelData; text: modelData }
}
```

For an existing `Flickable`, install `WheelPan { flickable: viewport }`
instead. `WheelPan` shares the `SmoothScroll` engine, respects `Motion`, and
keeps the existing distinction between mouse-wheel glides and touchpad pans.
The wrappers expose `wheelHandler` for programmatic scrolling through its
`smooth` object. `StitchListView.wheelScrolling` includes wheel activity and the
remaining animation, useful for logs that pause automatic following while
someone scrolls back.

`StitchPage` is a themed `Page` with a vertically scrolling `ColumnLayout` body.
Its default children go into that layout; use `Layout.fillWidth` for fields
and sections, and give custom items an implicit or preferred height. `title`
and `description` form a wrapping heading outside the scroll area. The
inherited `header` and `footer` slots can be replaced with custom items and
stay fixed while the body scrolls. `padding` and `contentSpacing` control the
body's spacing. Keyboard focus reveals fields in the body automatically.

```qml
StitchPage {
    anchors.fill: parent
    title: qsTr("Preferences")
    description: qsTr("Choose how the editor behaves.")
    StitchTextField { Layout.fillWidth: true; placeholderText: qsTr("Name") }
    StitchSwitch { text: qsTr("Enable hints") }
    footer: RowLayout {
        Item { Layout.fillWidth: true }
        StitchButton { text: qsTr("Save"); onClicked: host.save() }
    }
}
```

`StitchScreenDialog` combines that form body with `StitchDialog`'s themed title,
close button and standard footer actions. It sizes to its content up to the
window bounds, then scrolls the body. `preferredWidth` defaults to 560 and
`windowMargin` to 16. `description`, `contentSpacing` and `scrollView` are
also available. Set an explicit `height` when a screen needs a stable size.
Keep `StitchDialog` for specialized content that manages its own viewport.

```qml
StitchScreenDialog {
    title: qsTr("Options")
    standardButtons: Dialog.Ok | Dialog.Cancel
    StitchTextField { Layout.fillWidth: true }
    onAccepted: host.save()
}
```

These examples need `QtQuick`, `QtQuick.Controls`, `QtQuick.Layouts` and
`com.blockworked.Blockstitch 1.0`. The host owns navigation, validation,
persistence and commands; these components supply presentation and scrolling.
