# Hosting the block editor

How an app puts blockstitch's editor on its own blocks, and which host
features now live here (see Migration notes).
The core's own contract is in `crates/blockstitch-core/README.md`; the QML
module's in `qml/README.md`.

## Who owns what

| Layer | Lives in | A host brings |
| --- | --- | --- |
| Document, edits, undo steps, values, evaluation | `blockstitch-core` | an instruction enum (`BlockKind`), optional operators |
| Canvas, palette, palette drags, definition editor, theme | `qml/Blockstitch` (`com.blockworked.Blockstitch`) | block rows, labels, icons, the commands a drop becomes |
| Browser/C boundary | `blockstitch-ffi` | a `Host` type that dispatches commands |

Running blocks, saving files, history scope, notifications and anything
that reads the machine or the game world stay in the host.

## A minimal desktop host

Rust side: a vocabulary and a document. The crate README has the same
host as a compiled doctest.

```rust
use blockstitch_core::editor::{EditCommand, EditContext, History};
use blockstitch_core::graph::{BlockGraph, BlockKind, InputValueType, Instruction, RefKind};
use blockstitch_core::value::Value;

#[derive(Debug, Clone, PartialEq, Hash, serde::Serialize, serde::Deserialize)]
#[serde(tag = "type")]
enum Block {
    Start,
    Say { text: Value },
    SetVariable { name: String, value: Value },
    Repeat { count: Value, body: Vec<Instruction<Block>> },
}

impl BlockKind for Block {
    fn visit_values_mut(&mut self, f: &mut dyn FnMut(&mut Value, InputValueType)) {
        match self {
            Block::Say { text } => f(text, InputValueType::Any),
            Block::SetVariable { value, .. } => f(value, InputValueType::Any),
            Block::Repeat { count, .. } => f(count, InputValueType::Any),
            Block::Start => {}
        }
    }
    fn is_header(&self) -> bool { matches!(self, Block::Start) }
    fn body(&self, slot: u8) -> Option<&Vec<Instruction<Block>>> {
        match (self, slot) { (Block::Repeat { body, .. }, 0) => Some(body), _ => None }
    }
    fn body_mut(&mut self, slot: u8) -> Option<&mut Vec<Instruction<Block>>> {
        match (self, slot) { (Block::Repeat { body, .. }, 0) => Some(body), _ => None }
    }
    // The field ids the QML rows below name, so typing and drops reach the slot.
    fn value_slot_mut(&mut self, field: &str) -> Option<&mut Value> {
        match (self, field) {
            (Block::Say { text }, "SayText") => Some(text),
            (Block::SetVariable { value, .. }, "SetVariableValue") => Some(value),
            (Block::Repeat { count, .. }, "RepeatCount") => Some(count),
            _ => None,
        }
    }
    // Every name held as text: renames, packs and usage scans read this.
    fn visit_refs_mut(&mut self, f: &mut dyn FnMut(RefKind, &mut String)) {
        if let Block::SetVariable { name, .. } = self { f(RefKind::Variable, name) }
    }
}

// One gesture, one undo step: prepare reads, commit writes, under one lock.
fn run(graph: &mut BlockGraph<Block>, history: &mut History<BlockGraph<Block>>, cmd: EditCommand<Block>) -> Result<(), String> {
    let prepared = graph.prepare_edit(cmd, &EditContext::default()).map_err(String::from)?;
    if prepared.changes() {
        history.checkpoint(graph.clone(), prepared.coalesce().cloned());
    }
    let outcome = graph.commit_edit(prepared);
    if outcome.changed { /* save and publish state */ }
    Ok(())
}
```

Send the frontend `graph::to_frontend(&doc)` and read its instructions back
with `graph::from_frontend`, so only real instruction positions are
flattened. Copy, paste and duplicate are `copy_fragment`,
`EditCommand::PasteFragment` and `EditCommand::DuplicateInstruction`; every
pasted block gets a fresh id and `outcome.ids` maps old to new.

QML side: register the vocabulary once, then put the canvas, the palette and
one drag controller in a page.

```qml
import com.blockworked.Blockstitch 1.0

Item {
    id: page
    Component.onCompleted: {
        BlockRegistry.registerRows({
            Start: { shape: "header", head: [{ kind: "label", text: qsTr("when started") }] },
            Say: { icon: "message-square", head: [{ kind: "label", text: qsTr("say") }, { kind: "value", field: "SayText", key: "text" }] },
            Repeat: { icon: "repeat", head: [{ kind: "label", text: qsTr("repeat") }, { kind: "value", field: "RepeatCount", key: "count" }], mouths: ["body"] }
        });
        BlockRegistry.registerDescriptors(app.hostDescriptors) // host_operator_descriptors() as JSON, if any
    }
    PalettePanel {
        id: palette
        onDragStarted: (spec, sx, sy, ox, oy) => drags.begin(spec, sx, sy, ox, oy)
        onDragMoved: (sx, sy) => drags.move(sx, sy)
        onDragEnded: (sx, sy) => drags.end(sx, sy)
        onDragCanceled: drags.cancel()
    }
    BlockCanvas {
        id: canvas
        // strands, floatingValues, ... from the host's state. Optional run
        // marks: runningIds, breakpointIds, pausedIds, blockMarks ({id: text}),
        // answered by onMarkClicked / onBreakpointClicked.
    }
    PaletteDragController {
        id: drags
        anchors.fill: parent
        canvas: canvas
        documentId: app.currentDocumentId     // a change cancels a drag
        document: app.currentDocument.strands // the drop's ghost stays until this changes
        trashContains: (sx, sy) => palette.contains(palette.mapFromItem(null, sx, sy))
        // edit.kind is insert_instruction, add_strand, put_value,
        // create_floating_value, remove_instructions, remove_strand,
        // take_value or remove_floating_value: map it onto your commands.
        // drags.addAtView(spec) drops an entry at the view's centre (double-click).
        submit: (edit, reply) => app.invoke(edit.kind, edit, () => reply(true), e => reply(false, e))
    }
}
```

The palette groups blocks by category. Give it `sections` to order them
within one: `[{category, title, action, items}]`, where `items` names
instruction types and ops plus `@variables`, `@lists` or `@dicts`, and
`action` (`makeVariable`, `makeList`, `makeDict`) puts that button by the
title. Any other `action` is the host's own: `actionText` labels the button and
a click sends `sectionActionRequested(action)`. Blocks no section names join an untitled section at the end of their
category; without `sections`, variables, lists and dicts still get their own.

The built-in categories are Events, Flow, Data and Operators, then Custom.
`appCategories: [{id, name, icon, after}]` adds the host's own: one with
`after` sits behind that category, the rest go before Custom.
`accordionCategory` names the one the accordion layout opens on.

Fresh values come from the core: `BlockRegistry.freshValue(kind, names)` for
an operator, `BlockRegistry.freshCallArgs(definition)` for a custom block
call. Don't keep operator defaults in QML; change the Rust `default_args`
and re-bless the generated tables (`BLESS=1`, see `qml/README.md`).

Make a Block is `BlockDefinitionEditor`: set `allowBranches`,
`allowDefaults`, `allowCustomColor` and `shapes` to what the runtime can
run, `load(def)` or `reset()`, and send its `createRequested(draft)` /
`editRequested(blockId, draft)` to `BlockGraph::create_block`/`update_block`
plus `set_block_details` for the identifier, description and icon. The core
reconciles every call site, branch bodies included.

## Reproducible runs

`blockstitch_core::sources` is where fresh ids, `pick random` and `current
(time)` come from. The default is a v4 uuid, the thread rng and the local
clock. A replay test or a page compared against the app installs
deterministic ones for its thread:

```rust
use blockstitch_core::sources::{Seeded, with_sources};
let clock = chrono::NaiveDate::from_ymd_opt(2026, 1, 1).unwrap().and_hms_opt(12, 0, 0).unwrap();
let trace = with_sources(Seeded::new(42, clock), || run_the_script());
```

`set_sources(Some(Box::new(...)))` does the same until replaced, for a
session that lives across calls.

## In a browser (Qt for WebAssembly)

The page links the same core. The host crate implements
`blockstitch_ffi::Host` over its document and expands the macro once:

```rust
#[derive(Default)]
pub struct Page { doc: MyDocument, history: History<MyDocument> }

impl blockstitch_ffi::Host for Page {
    fn dispatch(&mut self, command: &str, args: &serde_json::Value) -> Result<serde_json::Value, String> {
        match command {
            "move_value" => { /* blockstitch_ffi::run_edit(&mut self.doc, ...) */ Ok(json!(null)) }
            "state" => Ok(blockstitch_core::graph::to_frontend(&self.doc).map_err(|e| e.to_string())?),
            other => Err(format!("`{other}` needs the app")), // say so, never ignore
        }
    }
}
blockstitch_ffi::export_abi!(Page);
```

Build it as a `staticlib` for `wasm32-unknown-emscripten` with
`panic = "abort"` (Qt's single-threaded wasm build uses JS exceptions, Rust's
emscripten std wasm ones; they don't link together) and link the `.a` into
the Qt executable. C++ calls `bs_session_new`, then
`bs_dispatch(handle, "{\"command\":..., \"args\":{...}}")`, which answers
`{"ok", "result", "error"}`; free every answer with `bs_string_free`
(`include/blockstitch_ffi.h`). The QML module comes from the same manifest
through `cmake/BlockstitchQml.cmake`. Blockwork's `blockwork-web` crate and
blockworked.com's `qt-demo/` (`core.cpp`, `DemoBackend.qml`) are the working
example; the site pins one Blockwork commit in `qt-demo/sources.env` and
reads blockstitch's from that commit's `Cargo.lock`.

## Names blockstitch knows

The QML draws a few instruction types itself, so a host's `InstructionKind`
must use these names (the `type` tag) and field keys for them:

| Type | Drawn as | Keys it reads |
| --- | --- | --- |
| `If`, `While` | wrap with a condition | `condition`, `body` |
| `IfElse` | two mouths, "else" between | `condition`, `then_body`, `else_body` |
| `Repeat` | wrap with a count | `count`, `body` |
| `Forever` | wrap | `body` |
| `Return`, `EscapeLoop`, `ContinueLoop` | cap (nothing snaps under) | `value` (`Return`) |
| `SetVariable`, `ChangeVariable` | the Variables palette section | `name`, `value` |
| `AddToList`, `DeleteOfList`, `DeleteAllOfList`, `ShiftList`, `InsertIntoList`, `ReplaceItemOfList`, `ReverseList` | the list blocks (rows in `defaultRows`) | `name` (the list), `value`, `index`, `amount` |
| `BlockHeader` | a custom block's definition hat | `block_id` |
| `CallBlock`, `BranchCallBlock` | a call, the second with mouths | `block_id`, `args`, `branches` |
| `RunBranch` | a call's branch placeholder | `name` |

`Wait` only gets a default icon and the "control" category; a host that has
one draws its row. Any other type whose name starts with `When` is a header (a hat with nothing
above it). Everything else comes from the host's rows in `BlockRegistry`.
Reporters `Text`, `Number`, `Bool` and `Op` are the `Value` kinds from
`blockstitch-core`.

## Reporter branches

A custom reporter with branches (`Value::Call { branches, .. }`) draws each
branch as a mouth the user can drop blocks into. The canvas has no strand for
it, so `ValueChip.branchId` names one: `@reporter-branch:` followed by JSON
`{"location": <the reporter's ValueLocation>, "slot": <branch index>}`. That id
arrives wherever the host's command puts a strand id.

`editor::reporter_branch_ids(&args, keys)` lists them; `BranchArgKeys` names
the host's strand id arguments and the arguments that hold a `ValueLocation`
(Blockwork's are `BRANCH_ARG_KEYS` in the file below). Run the edit on a clone of
the graph between `open_reporter_branches` (each branch becomes a temporary
strand; the host's closure reads its saved JSON body as instructions) and
`close_reporter_branches` (writes each back into its reporter's
`branches[slot]`, and refuses a header there or a reporter moved into its own
branch). Commit the clone only when closing succeeds. Blockwork does this in
`blockwork-core/src/frontend/reporter_branches.rs`, which its desktop app and
its website build both call.

## Pins

A host pins `blockstitch-core`, `blockstitch-qml` (and `blockstitch-ffi` if
used) to one commit, and moves them together. Blockwork's
`scripts/set-blockstitch-rev.js` and Blockloom's `just blockstitch-published`
do that; Blockwork's also moves the flatpak manifest, after which its
`packaging/flatpak/cargo-sources.json` is regenerated with
`flatpak-cargo-generator`. `just blockstitch-local` builds against a sibling
checkout through an uncommitted `.cargo/config.toml`; delete it before
committing.

## Migration notes

| Old | Now |
| --- | --- |
| `BlockKind::variable_target_mut` / `list_target_mut` / `dict_target_mut` | removed; implement `visit_refs_mut` (one call per name, any number) |
| `uuid`/`rand`/`chrono::Local` called directly by the core | `blockstitch_core::sources` (default unchanged) |
| Host-side value move as take then put (two undo steps) | `EditCommand::MoveValue` (`move_value`), one step |
| One `remove_instruction` per block of a trashed tail | `RemoveInstructions { count }` |
| QML `refreshIds` / `regenerateIds` on paste | `PasteFragment` / `DuplicateInstruction` in the core, fresh ids |
| JSON heuristics flattening `{id, kind}` objects for the frontend | `graph::to_frontend` / `from_frontend` |
| Operator default args in each app's QML | `operator_descriptors()` and generated `BlockRegistry` tables |
| Battery/clipboard reporters, recording menu and automation icons in the shared registry | registered by Blockwork (`registerIcons`, `blockMenu`, `strandMark` with `BlockCanvas.markedStrandId`) |
| Icons only Blockwork's blocks drew (battery, clipboard, terminal, ...) in `Icons.qml` | the host passes its own set to `Icons.add` |
| `reporter_branch_ids(&args)` guessing Blockwork's argument names | `reporter_branch_ids(&args, BranchArgKeys { .. })` |
| `BlockRegistry.runningIds`, `breakpointIds`, `pausedIds`, `blockMarks`, `markClicked`, `breakpointClicked` | the same names on `BlockCanvas` (held per canvas in its `CanvasState`) |
| Each app's palette drag code | `PaletteDragController` |
| Each app's Make a Block dialog | `BlockDefinitionEditor` |
| Each app's custom-call argument builder | `BlockRegistry.freshCallArgs` |
| QML file lists in `build.rs` and the site's CMake | `qml/module.json` |
| `blockstitch-ffi` ABI v1 (a fixed stand-in document) | ABI v2: `Host` + `export_abi!` |
| `BlockRegistry.recordingTargets`, `BlockCanvas.recordingTargetId`, `recordingTargetRequested` | a host `blockMenu` item; `BlockCanvas.markedStrandId` + `BlockRegistry.strandMark` for the badge |

Saved files are unchanged except that custom block definitions now always
carry `identifier`, `description` and `icon` (empty when unset); files
without them load.

## Known limits

- `BlockRegistry` is one per QML engine, so two canvases in one engine share
  their vocabulary, menus, the list/variable names dropdowns offer, and
  click-to-preview (each request is keyed, so answers reach the right chip).
  Run and debug marks are per canvas (`CanvasState`).
- `Value::Call::branches` is opaque JSON; ids inside it aren't renamed on
  paste, and a host has to route reporter-branch edits itself (see above).
- A panic in the browser core aborts the module; the page offers a reload.
