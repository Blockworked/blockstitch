# Blockstitch QML frontend

This directory is the Qt 6 counterpart to the existing Vue frontend in
`src/`. It intentionally does not replace or modify the browser package.

The components are registered as the `com.blockworked.Blockstitch` QML module
by the `blockstitch-qml` crate. `BlockCanvas` renders draggable Scratch-style strands on a zoomable
dotted workspace, while `PalettePanel` and the small controls share the same
dark, beveled visual language as the browser UI.

Native consumers depend on the repository's root Cargo package and call
`blockstitch_qml::init()` before creating their QML engine. The existing npm
package and everything under `src/` remain the browser implementation.

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

## Registering an app's blocks

`BlockRegistry` is the QML side of the Vue `register*` calls. An app describes
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

A type without a row falls back to the built-in classic rows. `shape`
(`"header"`/`"cap"`) and `mouths` (the instruction keys holding nested
bodies) decide a block's outline; the comments in `BlockRegistry.qml` list
every piece kind. `blockMenu`/`canvasMenu` add app-specific context menu
items, which come back through `blockMenuAction`/`canvasMenuAction`. An
operator's `enumArg` may give its choices as an array, a function, or
`"lists"`/`"dicts"` for the collection names the canvas was given. Its
`pickArg: {index, action, icon}` puts a button after that arg while it holds
text; a click calls `BlockRegistry.pickHandler(action, location, value)` with
the slot's location, so the host can open a picker and write the choice back
like a typed edit.

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

Nothing host-specific: no recording-target menu entry (`recordingTargets` is
off), no battery or clipboard reporters, and icon fallbacks only for the
shared control and data blocks. A host turns its features on and registers
the rest (`registerIcons({MoveMouse: "move"})`).

A row whose pieces depend on the instruction (one generic type that many
app-defined blocks share) gives `head` as a function of the instruction, and
a piece (value, dropdown or text) may carry `index` to read and write one entry
of an array held under its `key` instead of the key itself.

The same goes for an operator many app-defined reporters share: `layout` is an
array (or a function of the value) of `{label, arg: -1}` and `{arg, bool}` pieces, and
the args it does not name are not drawn, so a generic `PluginRead(plugin,
block, ...slots)` can show only its label and slots. `result` may likewise be a
function of the value, so such a reporter takes the boolean shape when its
block answers true or false.

## Dicts

`BlockCanvas.dicts` and `PalettePanel.dicts` take the document's dicts
(`{name, entries: [{key, value}], editor_visible, editor_x, editor_y}`).
Visible ones get an editor card on the canvas that reports edits through
`dictEntriesEdited`/`dictEditorStateChanged`, and the palette lists them in a
`CollectionPanel` beside the lists with their reporters (`DictValue`,
`DictHasKey`, `DictSize`, `DictKeys`, `DictAsJson`, `DictIsEmpty`).
