//! The backend half of blockstitch: the document model, value system and
//! editing operations behind a Scratch-style block editor. The Vue
//! components in this repo render a canvas; this crate is what it edits.
//!
//! A host brings an instruction enum implementing [`graph::BlockKind`], a
//! document owning a [`graph::BlockGraph`], and optionally its own operators
//! (see [`value::register_operators`]). See the README for the full contract.
//!
//! ```no_run
//! use blockstitch_core::graph::{BlockGraph, BlockKind, InputValueType, Instruction};
//! use blockstitch_core::value::Value;
//! use serde::{Deserialize, Serialize};
//!
//! #[derive(Debug, Clone, PartialEq, Hash, Serialize, Deserialize)]
//! enum Block {
//!     Start,
//!     Say(Value),
//!     Repeat { count: Value, body: Vec<Instruction<Block>> },
//! }
//!
//! impl BlockKind for Block {
//!     fn visit_values_mut(&mut self, f: &mut dyn FnMut(&mut Value, InputValueType)) {
//!         match self {
//!             Block::Say(value) => f(value, InputValueType::Any),
//!             Block::Repeat { count, .. } => f(count, InputValueType::Any),
//!             Block::Start => {}
//!         }
//!     }
//!     fn is_header(&self) -> bool {
//!         matches!(self, Block::Start)
//!     }
//!     fn body_mut(&mut self, slot: u8) -> Option<&mut Vec<Instruction<Block>>> {
//!         match (self, slot) {
//!             (Block::Repeat { body, .. }, 0) => Some(body),
//!             _ => None,
//!         }
//!     }
//! }
//!
//! let mut graph: BlockGraph<Block> = BlockGraph::new();
//! graph.add_strand(0, 0, vec![Instruction::new(Block::Start)]);
//! ```

pub mod editor;
pub mod graph;
pub mod value;

pub use graph::{BlockGraph, BlockKind, Instruction, ListDef, ListItem, ListStore};
pub use value::{Evaluated, Op, Value};
