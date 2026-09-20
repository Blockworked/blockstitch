//! The editing layer: addressing, undo history, and every mutation a
//! canvas gesture performs on a [`crate::graph::BlockGraph`].

mod history;
mod location;
mod ops;
mod path;

pub use history::{EditSession, History};
pub use location::{
    ValueBuffers, ValueLocation, drop_strand_buffers, prune_value_buffers, retain_live_buffers,
};
pub use ops::{ValueEdit, apply_value_kind};
pub use path::{InstrPath, PathStep, resolve_body, resolve_body_mut};
