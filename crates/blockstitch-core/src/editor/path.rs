//! Addressing an instruction on the canvas: which strand, then which index
//! at which nesting level.

use crate::graph::{BlockKind, Instruction};
use serde::{Deserialize, Serialize};

/// One step of an [`InstrPath`]: an index into an instruction list, plus
/// which nested body to descend into next (`None` on the last step).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub struct PathStep {
    pub index: usize,
    pub slot: Option<u8>,
}

impl PathStep {
    /// A final step - addresses `index` in the list reached so far.
    pub fn at(index: usize) -> Self {
        Self { index, slot: None }
    }

    /// A descending step - into `slot`'s body of the instruction at `index`.
    pub fn into_body(index: usize, slot: u8) -> Self {
        Self {
            index,
            slot: Some(slot),
        }
    }
}

/// Addresses one instruction, possibly nested. A single-step path is a
/// strand's own top level.
pub type InstrPath = Vec<PathStep>;

/// Resolves an [`InstrPath`] to `(parent_list, local_index)` - read-only
/// counterpart to [`resolve_body_mut`], for checks that only look.
pub fn resolve_body<'a, K: BlockKind>(
    instructions: &'a [Instruction<K>],
    path: &[PathStep],
) -> Option<(&'a [Instruction<K>], usize)> {
    let (first, rest) = path.split_first()?;
    if rest.is_empty() {
        return Some((instructions, first.index));
    }
    let body = instructions.get(first.index)?.body(first.slot?)?;
    resolve_body(body, rest)
}

/// Resolves an [`InstrPath`] to `(parent_list, local_index)` - every
/// instruction edit does its `Vec` op on that list at that index. The index
/// isn't bounds-checked: an insert may legitimately be one past the end.
pub fn resolve_body_mut<'a, K: BlockKind>(
    instructions: &'a mut Vec<Instruction<K>>,
    path: &[PathStep],
) -> Option<(&'a mut Vec<Instruction<K>>, usize)> {
    let (first, rest) = path.split_first()?;
    if rest.is_empty() {
        return Some((instructions, first.index));
    }
    let body = instructions.get_mut(first.index)?.body_mut(first.slot?)?;
    resolve_body_mut(body, rest)
}
