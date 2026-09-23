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
| `editor` | `PathStep`/`ValueLocation` addressing, the undo `History`, and every structural edit a canvas gesture performs   |

Editor operations validate first and mutate second, and none of them lock,
save or notify - a host wraps them in whatever state handling it already has.

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

That's the whole contract. `BlockGraph<Block>` is now a working canvas.
