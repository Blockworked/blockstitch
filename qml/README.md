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

A type without a row falls back to the built-in Blockwork rows. `shape`
(`"header"`/`"cap"`) and `mouths` (the instruction keys holding nested
bodies) decide a block's outline; the comments in `BlockRegistry.qml` list
every piece kind. `blockMenu`/`canvasMenu` add app-specific context menu
items, which come back through `blockMenuAction`/`canvasMenuAction`. An
operator's `enumArg` may give its choices as an array, a function, or
`"lists"`/`"dicts"` for the collection names the canvas was given.

## Dicts

`BlockCanvas.dicts` and `PalettePanel.dicts` take the document's dicts
(`{name, entries: [{key, value}], editor_visible, editor_x, editor_y}`).
Visible ones get an editor card on the canvas that reports edits through
`dictEntriesEdited`/`dictEditorStateChanged`, and the palette lists them in a
`CollectionPanel` beside the lists with their reporters (`DictValue`,
`DictHasKey`, `DictSize`, `DictKeys`, `DictAsJson`, `DictIsEmpty`).
