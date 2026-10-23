# blockstitch-core

The backend half of blockstitch: the document model, value system and editing
operations behind a Scratch-style block editor. The Vue components in this
repo render a canvas; this crate is what the canvas edits.

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

```rust
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

```rust
use blockstitch_core::graph::{BlockGraph, BlockKind, InputValueType, Instruction};
use blockstitch_core::value::Value;
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, PartialEq, Hash, Serialize, Deserialize)]
enum Block {
    Start,
    Say(Value),
    Repeat { count: Value, body: Vec<Instruction<Block>> },
}

impl BlockKind for Block {
    fn visit_values_mut(&mut self, f: &mut dyn FnMut(&mut Value, InputValueType)) {
        match self {
            Block::Say(value) => f(value, InputValueType::Any),
            Block::Repeat { count, .. } => f(count, InputValueType::Any),
            Block::Start => {}
        }
    }
    fn is_header(&self) -> bool {
        matches!(self, Block::Start)
    }
    fn body_mut(&mut self, slot: u8) -> Option<&mut Vec<Instruction<Block>>> {
        match (self, slot) {
            (Block::Repeat { body, .. }, 0) => Some(body),
            _ => None,
        }
    }
}
```

That's the whole contract. `BlockGraph<Block>` is now a working canvas. A
block that holds a variable, list or dict name as text also reports it from
`visit_refs_mut`, so renames reach it. `docs/hosting.md` walks through a
full desktop and browser host.
