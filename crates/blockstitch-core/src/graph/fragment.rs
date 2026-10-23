//! Copying blocks: a [`Fragment`] is a run of instructions lifted off a
//! canvas with the notes pinned to them, and pasting one clones it with
//! fresh ids through the kind's declared bodies.
//!
//! Policy, for a paste into the same canvas or another one:
//! - Every instruction and carried note gets a new id; the [`IdMap`] says
//!   which old id became which. Notes stay pinned to their clone.
//! - Variable, list and dict names are kept as written. Whether one resolves
//!   is the host's question at run time, as for any other block.
//! - A call to a custom block the target doesn't define is refused, and so
//!   is a custom block's own header: a definition can't be copied this way.
//! - `Value::Call::branches` is host JSON and is copied verbatim.

use crate::editor::{EditError, PathStep, resolve_body};
use crate::graph::canvas::Comment;
use crate::graph::instruction::{BlockKind, Instruction};
use crate::graph::{BlockGraph, new_id};
use serde::{Deserialize, Serialize};
use std::collections::{BTreeMap, BTreeSet, HashSet};

/// Old id to new id, for every instruction a clone renamed.
pub type IdMap = BTreeMap<String, String>;

/// Instructions copied off a canvas, plus the notes attached to them.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(bound(serialize = "K: Serialize", deserialize = "K: Deserialize<'de>"))]
pub struct Fragment<K> {
    pub instructions: Vec<Instruction<K>>,
    /// Only notes whose `attached_to` is inside `instructions` are kept.
    #[serde(default)]
    pub comments: Vec<Comment>,
}

impl<K> Fragment<K> {
    pub fn new(instructions: Vec<Instruction<K>>) -> Self {
        Self {
            instructions,
            comments: Vec::new(),
        }
    }
}

impl<K: BlockKind> Instruction<K> {
    /// A copy with a fresh id on it and everything nested in it, recording
    /// each rename in `ids`.
    pub fn clone_fresh(&self, ids: &mut IdMap) -> Instruction<K> {
        let mut copy = self.clone();
        copy.walk_mut(&mut |ins| {
            let fresh = new_id();
            ids.insert(std::mem::replace(&mut ins.id, fresh.clone()), fresh);
        });
        copy
    }
}

impl<K: BlockKind> Fragment<K> {
    /// A copy with fresh instruction and note ids, notes re-pinned to the
    /// clones. Notes pinned to anything outside the fragment are dropped.
    pub fn clone_fresh(&self) -> (Fragment<K>, IdMap) {
        let mut ids = IdMap::new();
        let instructions = self
            .instructions
            .iter()
            .map(|ins| ins.clone_fresh(&mut ids))
            .collect();
        let comments = self
            .comments
            .iter()
            .filter_map(|comment| {
                let target = ids.get(comment.attached_to.as_deref()?)?;
                Some(Comment {
                    id: new_id(),
                    attached_to: Some(target.clone()),
                    ..comment.clone()
                })
            })
            .collect();
        (
            Fragment {
                instructions,
                comments,
            },
            ids,
        )
    }

    /// Every custom block the fragment calls, as a command or a reporter.
    pub fn called_blocks(&self) -> BTreeSet<String> {
        let mut out = BTreeSet::new();
        for root in &self.instructions {
            root.walk(&mut |ins| {
                if let Some(id) = ins.kind.called_block() {
                    out.insert(id.to_string());
                }
                ins.kind.clone().visit_values_mut(&mut |value, _| {
                    value.visit_block_calls(&mut |id| {
                        out.insert(id.to_string());
                    })
                });
            });
        }
        out
    }
}

impl<K: BlockKind> BlockGraph<K> {
    /// `count` instructions from `path` (the rest of that list when `None`),
    /// with their nested bodies and the notes pinned to any of them.
    pub fn copy_fragment(
        &self,
        strand_id: &str,
        path: &[PathStep],
        count: Option<usize>,
    ) -> Result<Fragment<K>, EditError> {
        let strand = self
            .strand(strand_id)
            .ok_or(EditError::Missing("Unknown strand"))?;
        let (list, index) = resolve_body(&strand.instructions, path)
            .ok_or(EditError::Missing("Unknown instruction path"))?;
        if index >= list.len() {
            return Err(EditError::Missing("Instruction index out of range"));
        }
        let end = match count {
            Some(count) => (index + count.max(1)).min(list.len()),
            None => list.len(),
        };
        let instructions = list[index..end].to_vec();
        Ok(Fragment {
            comments: self.comments_on(&instructions),
            instructions,
        })
    }

    /// Notes pinned to any of `instructions` or anything nested in them.
    pub(crate) fn comments_on(&self, instructions: &[Instruction<K>]) -> Vec<Comment> {
        let mut ids = HashSet::new();
        for root in instructions {
            root.walk(&mut |ins| {
                ids.insert(ins.id.clone());
            });
        }
        self.comments
            .iter()
            .filter(|c| c.attached_to.as_ref().is_some_and(|id| ids.contains(id)))
            .cloned()
            .collect()
    }

    /// Whether `fragment` can land here as a strand of its own: a header
    /// only first, no custom block definitions, no calls to blocks this
    /// canvas doesn't define.
    pub fn check_paste(&self, fragment: &Fragment<K>) -> Result<(), EditError> {
        let Some(first) = fragment.instructions.first() else {
            return Err(EditError::Rejected("Nothing to paste".to_string()));
        };
        if first.kind.block_header_id().is_some() {
            return Err(EditError::Rejected(
                "A custom block's definition can't be pasted".to_string(),
            ));
        }
        let mut misplaced = false;
        for (index, root) in fragment.instructions.iter().enumerate() {
            root.walk(&mut |ins| {
                misplaced |= ins.is_header() && !(index == 0 && std::ptr::eq(ins, root));
            });
        }
        if misplaced {
            return Err(EditError::Rejected(format!(
                "A {} block can only be the first block in a strand",
                K::HEADER_LABEL
            )));
        }
        let missing: Vec<String> = fragment
            .called_blocks()
            .into_iter()
            .filter(|id| self.block_def(id).is_none())
            .collect();
        if !missing.is_empty() {
            return Err(EditError::Rejected(format!(
                "This copy uses custom blocks this canvas doesn't have ({})",
                missing.join(", ")
            )));
        }
        Ok(())
    }
}
