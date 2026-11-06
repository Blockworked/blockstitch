//! Editing inside a custom reporter's branches. The canvas names a branch
//! with a strand id, `@reporter-branch:{"location": .., "slot": n}`
//! (`ValueChip.branchId` in the QML), since it has no strand of its own.
//! [`BlockGraph::open_reporter_branches`] adds each named branch as a
//! temporary strand, so any ordinary edit works on it, and
//! [`BlockGraph::close_reporter_branches`] writes them back.

use crate::editor::location::ValueLocation;
use crate::graph::{BlockGraph, BlockKind, Instruction, Strand};
use crate::value::Value;
use serde::Deserialize;
use serde_json::Value as Json;

/// What every reporter-branch strand id starts with.
pub const REPORTER_BRANCH_PREFIX: &str = "@reporter-branch:";

/// How deep branches may nest inside each other's reporters.
const MAX_OPEN: usize = 32;

/// The argument names the canvas puts strand ids and value locations in.
const ID_KEYS: [&str; 4] = ["strandId", "targetId", "draggedId", "strand_id"];
const LOCATION_KEYS: [&str; 3] = ["location", "from", "to"];

#[derive(Deserialize)]
struct BranchAddress {
    location: ValueLocation,
    slot: usize,
}

struct Branch {
    id: String,
    address: BranchAddress,
    owner: Option<String>,
}

/// Branches opened as temporary strands; hand back to
/// [`BlockGraph::close_reporter_branches`].
pub struct OpenBranches(Vec<Branch>);

/// Every reporter-branch strand id in a command's JSON arguments.
pub fn reporter_branch_ids(args: &Json) -> Vec<String> {
    let mut ids = Vec::new();
    collect_ids(args, &mut ids);
    ids
}

/// Whether a command's arguments name any reporter branch.
pub fn targets_reporter_branch(args: &Json) -> bool {
    !reporter_branch_ids(args).is_empty()
}

fn collect_ids(args: &Json, ids: &mut Vec<String>) {
    if let Json::Object(fields) = args {
        for (key, value) in fields {
            if ID_KEYS.contains(&key.as_str()) {
                if let Some(id) = value
                    .as_str()
                    .filter(|id| id.starts_with(REPORTER_BRANCH_PREFIX))
                {
                    ids.push(id.to_string());
                }
            } else if LOCATION_KEYS.contains(&key.as_str()) {
                collect_ids(value, ids);
            }
        }
    }
}

impl<K: BlockKind> BlockGraph<K> {
    /// Adds each named branch (and any branch its reporter sits in) as a
    /// temporary strand. `read` turns a branch's saved JSON body into
    /// instructions. Call it on a clone: on an error the graph is half open.
    pub fn open_reporter_branches(
        &mut self,
        ids: &[String],
        read: &dyn Fn(&[Json]) -> Result<Vec<Instruction<K>>, String>,
    ) -> Result<OpenBranches, String> {
        let mut open = Vec::new();
        for id in ids {
            self.open_branch(id, read, &mut open)?;
        }
        Ok(OpenBranches(open))
    }

    fn open_branch(
        &mut self,
        id: &str,
        read: &dyn Fn(&[Json]) -> Result<Vec<Instruction<K>>, String>,
        open: &mut Vec<Branch>,
    ) -> Result<(), String> {
        let Some(encoded) = id.strip_prefix(REPORTER_BRANCH_PREFIX) else {
            return Ok(());
        };
        if open.iter().any(|branch| branch.id == id) {
            return Ok(());
        }
        if open.len() >= MAX_OPEN {
            return Err("Reporter branches are nested too deeply".into());
        }
        let address: BranchAddress = serde_json::from_str(encoded).map_err(|e| e.to_string())?;
        // A reporter inside another branch: open that one first.
        let owner = if let ValueLocation::Field {
            strand_id, index, ..
        } = &address.location
        {
            self.open_branch(strand_id, read, open)?;
            Some(
                self.instruction_at(strand_id, index)
                    .ok_or("Reporter owner is missing")?
                    .id
                    .clone(),
            )
        } else {
            None
        };
        let Value::Call {
            branches: bodies, ..
        } = self
            .value_at_mut(&address.location)
            .ok_or("Reporter is missing")?
        else {
            return Err("The value is not a custom reporter".into());
        };
        if address.slot >= 255 {
            return Err("Invalid reporter branch".into());
        }
        bodies.resize_with(bodies.len().max(address.slot + 1), Vec::new);
        let instructions = read(&bodies[address.slot])?;
        self.strands.push(Strand {
            id: id.into(),
            x: 0,
            y: 0,
            instructions,
        });
        open.push(Branch {
            id: id.into(),
            address,
            owner,
        });
        Ok(())
    }

    /// Writes every opened branch back into its reporter, innermost first,
    /// and removes the temporary strands. `write` turns one instruction back
    /// into saved JSON. Refuses a header in a branch and a reporter moved
    /// into its own branch.
    pub fn close_reporter_branches(
        &mut self,
        open: OpenBranches,
        write: &dyn Fn(&Instruction<K>) -> Result<Json, String>,
    ) -> Result<(), String> {
        for branch in open.0.into_iter().rev() {
            self.close_branch(branch, write)?;
        }
        Ok(())
    }

    fn close_branch(
        &mut self,
        branch: Branch,
        write: &dyn Fn(&Instruction<K>) -> Result<Json, String>,
    ) -> Result<(), String> {
        let instructions = match self.strands.iter().position(|s| s.id == branch.id) {
            Some(index) => self.strands.remove(index).instructions,
            None => Vec::new(),
        };
        if instructions
            .iter()
            .any(|instruction| instruction.kind.is_header())
        {
            return Err("A header block can't be placed in a reporter branch".into());
        }
        let body = instructions
            .iter()
            .map(write)
            .collect::<Result<Vec<_>, _>>()?;
        let mut restored = false;
        if let (Some(owner), ValueLocation::Field { field_id, path, .. }) =
            (branch.owner, &branch.address.location)
        {
            // The owner may have moved, so find it by id.
            self.walk_instructions_mut(&mut |instruction| {
                if instruction.id == owner
                    && let Some(Value::Call { branches, .. }) = instruction
                        .kind
                        .value_slot_mut(field_id)
                        .and_then(|v| v.get_mut(path))
                    && let Some(slot) = branches.get_mut(branch.address.slot)
                {
                    *slot = body.clone();
                    restored = true;
                }
            });
        } else if let Some(Value::Call { branches, .. }) =
            self.value_at_mut(&branch.address.location)
            && let Some(slot) = branches.get_mut(branch.address.slot)
        {
            *slot = body;
            restored = true;
        }
        if restored {
            Ok(())
        } else {
            Err("Can't move a reporter into its own branch".into())
        }
    }
}
