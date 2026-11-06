# blockstitch-core

The backend half of blockstitch: the document model, value system and editing
operations behind a Scratch-style block editor. The QML module in this
repo renders the canvas; this crate is what the canvas edits.

It knows nothing about any particular app's blocks. A host brings three
things:

1. **an instruction enum implementing `graph::BlockKind`** - its own block
   vocabulary, describing where each block keeps its values and nested
   bodies, which blocks are headers, and how the frontend's field ids map
   onto its slots;
2. **operators, optionally** - `value::register_operators` adds app-specific
   reporter blocks on top of the built-in arithmetic/text/logic/time set;
3. **a document type owning a `graph::BlockGraph`** - plus whatever else it
   needs (a name, run settings, ...). `#[serde(flatten)]` on that field keeps
   the wire shape flat, and `Deref` keeps `doc.strands` reading the way it
   would if the collections were still its own fields.

Everything else already works the same for every host: walking nested bodies,
renaming a variable everywhere it's read or written, reconciling a custom
block's call sites when its inputs change, repairing legacy boolean slots,
resolving the value a drag targeted, dropping one in, and undo/redo.

## Layout

| module   | what's in it                                                                                                   |
| -------- | -------------------------------------------------------------------------------------------------------------- |
| `value`  | `Value` expression trees, `Evaluated` results, the built-in `Op` set, and the host operator registry             |
| `graph`  | `BlockGraph` (strands, instructions, parked values, notes, variables, lists, custom blocks) and the `BlockKind` trait   |
| `sources` | where fresh ids, random numbers and the clock come from (`Seeded` for replays)                         |
| `editor` | `PathStep`/`ValueLocation` addressing, the undo `History`, and every structural edit a canvas gesture performs   |

Editor operations validate first and mutate second, and none of them lock,
save or notify - a host wraps them in whatever state handling it already has.

A gesture that should be one undo step goes through `editor::EditCommand`
(move a value, type into a field, delete a tail, insert a block, paste a
copied fragment, duplicate a block):

```rust,ignore
let prepared = graph.prepare_edit(command, &EditContext::default())?; // reads only
if prepared.changes() {
    history.checkpoint(snapshot(), prepared.coalesce().cloned());
}
let outcome = graph.commit_edit(prepared);
apply_buffer_effects(&mut buffers, &outcome.buffers);
if outcome.changed { /* save, notify */ }
```

A rejected command is an `Err` and touches nothing; a valid no-op has
`changes() == false` and needs no history or save.

Copy and paste go through `graph::Fragment`: `BlockGraph::copy_fragment`
lifts instructions and the notes pinned to them, and `PasteFragment` or
`DuplicateInstruction` clones them with fresh ids through every body
`BlockKind::body` declares (`outcome.ids` maps old ids to new). A paste that
calls a custom block the canvas doesn't define, or carries a definition's
header, is refused.

Fresh ids, `pick random` and `current (time)` go through `sources`; a host
installs `sources::Seeded` (or its own) per thread for reproducible runs.

Documents store an instruction as `{"id", "kind": {...}}`. A frontend that
wants the flat `{"id", "type", ...}` node shape uses `graph::to_frontend` /
`graph::from_frontend`, which flatten only real `Instruction` positions, so
host JSON inside a kind is left alone. The kind must serialize as an object
(an internally tagged enum).

## Example

A small host, compiled and run as this crate's doctest:

```rust
use blockstitch_core::editor::{EditCommand, EditContext, PathStep, ValueLocation};
use blockstitch_core::graph::{BlockGraph, BlockKind, InputValueType, Instruction, RefKind};
use blockstitch_core::value::Value;
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, PartialEq, Hash, Serialize, Deserialize)]
#[serde(tag = "type")]
enum Block {
    Start,
    Say { text: Value },
    SetVariable { name: String, value: Value },
    Repeat { count: Value, body: Vec<Instruction<Block>> },
}

impl BlockKind for Block {
    // Every value slot the block owns (not those in its bodies).
    fn visit_values_mut(&mut self, f: &mut dyn FnMut(&mut Value, InputValueType)) {
        match self {
            Block::Say { text } => f(text, InputValueType::Any),
            Block::SetVariable { value, .. } => f(value, InputValueType::Any),
            Block::Repeat { count, .. } => f(count, InputValueType::Any),
            Block::Start => {}
        }
    }
    fn is_header(&self) -> bool {
        matches!(self, Block::Start)
    }
    // Nested bodies: `body` for walks and copies, `body_mut` for edits.
    fn body(&self, slot: u8) -> Option<&Vec<Instruction<Block>>> {
        match (self, slot) {
            (Block::Repeat { body, .. }, 0) => Some(body),
            _ => None,
        }
    }
    fn body_mut(&mut self, slot: u8) -> Option<&mut Vec<Instruction<Block>>> {
        match (self, slot) {
            (Block::Repeat { body, .. }, 0) => Some(body),
            _ => None,
        }
    }
    // The field ids the QML rows name, so typing and drops reach the slot.
    fn value_slot_mut(&mut self, field: &str) -> Option<&mut Value> {
        match (self, field) {
            (Block::Say { text }, "SayText") => Some(text),
            (Block::SetVariable { value, .. }, "SetVariableValue") => Some(value),
            (Block::Repeat { count, .. }, "RepeatCount") => Some(count),
            _ => None,
        }
    }
    // Names held as text, so renames reach them.
    fn visit_refs_mut(&mut self, f: &mut dyn FnMut(RefKind, &mut String)) {
        if let Block::SetVariable { name, .. } = self {
            f(RefKind::Variable, name);
        }
    }
}

let mut graph: BlockGraph<Block> = BlockGraph::new();
graph.create_variable("score").unwrap();
let strand = graph.add_strand(0, 0, vec![
    Instruction::new(Block::Start),
    Instruction::new(Block::Repeat {
        count: Value::number(3.0),
        body: vec![Instruction::new(Block::SetVariable { name: "score".into(), value: Value::number(0.0) })],
    }),
]);

// Typing into the repeat's count is one edit command (one undo step).
let count = ValueLocation::Field {
    strand_id: strand.clone(),
    index: vec![PathStep::at(1)],
    field_id: "RepeatCount".into(),
    path: vec![],
};
let edit = EditCommand::EditFieldText { location: count.clone(), text: "5".into() };
graph.apply_edit(edit, &EditContext::default()).unwrap();
assert_eq!(graph.value_at(&count), Some(Value::number(5.0)));

// A rename reaches the block inside the loop's body.
graph.rename_variable("score", "points").unwrap();
let json = serde_json::to_string(&graph).unwrap();
assert!(json.contains("\"points\"") && !json.contains("\"score\""));
```

`BlockKind` has defaults for the rest (custom block calls, integer-only
fields, ...); `src/graph/instruction.rs` documents each. `docs/hosting.md`
(at the repo root) walks through a full desktop and browser host.
