//! The document model: what a canvas holds, and the block vocabulary hook
//! a host app fills in.

mod block;
mod canvas;
mod document;
mod instruction;
mod lists;

pub use block::{
    BlockDef, BlockPiece, BlockShape, InputValueType, default_block_color, normalize_block_color,
};
pub use canvas::{Comment, FloatingValue, Strand, VariableDef};
pub use document::BlockGraph;
pub use instruction::{BlockKind, Instruction};
pub use lists::{
    ListDef, ListItem, ListStore, is_list_reporter, list_index, list_reporter_name_index,
    rename_list_in_value, resolve_list_reporter, resolve_list_reporters,
};

/// Ids for everything on the canvas - a bare uuid, since they only have to
/// be unique within one document.
pub fn new_id() -> String {
    uuid::Uuid::new_v4().simple().to_string()
}
