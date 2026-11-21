//! The canvas commands a host runs inside a custom reporter's branches.
//! Every host spells their arguments the same way (`strandId`, `path`,
//! `targetId`, ...), so one runner serves all of them.

use crate::editor::reporter_branch::{BranchArgKeys, BranchReader, reporter_branch_ids};
use crate::editor::{EditCommand, EditContext, PathStep, ValueDestination, ValueLocation};
use crate::graph::{BlockGraph, BlockKind, Fragment, Instruction};
use serde::de::DeserializeOwned;
use serde_json::{Value as Json, json};

/// Where the canvas commands keep strand ids and value locations.
pub const CANVAS_ARG_KEYS: BranchArgKeys<'static> = BranchArgKeys {
    ids: &["strandId", "targetId", "draggedId"],
    locations: &["location", "from", "to"],
};

/// The commands [`BlockGraph::edit_reporter_branch`] runs.
pub const BRANCH_COMMANDS: &[&str] = &[
    "add_instruction",
    "edit_instruction",
    "merge_strand",
    "merge_tail",
    "split_strand",
    "move_strand",
    "remove_strand",
    "remove_instruction",
    "duplicate_instruction",
    "copy_instructions",
    "edit_value_field",
    "put_value",
    "take_value",
    "move_value",
];

/// How a host turns its instructions into the JSON a reporter keeps and
/// the canvas sends, and back.
pub struct BranchCodec<'a, K> {
    /// A branch's saved body into instructions.
    pub read: &'a BranchReader<'a, K>,
    /// One instruction into saved body JSON.
    pub write: &'a dyn Fn(&Instruction<K>) -> Result<Json, String>,
    /// An `instruction` argument from the canvas.
    pub instruction: &'a dyn Fn(&Json) -> Result<Instruction<K>, String>,
    /// A copied fragment as the canvas wants it back.
    pub fragment: &'a dyn Fn(&Fragment<K>) -> Result<Json, String>,
}

fn arg<T: DeserializeOwned>(args: &Json, name: &str) -> Result<T, String> {
    serde_json::from_value(args.get(name).cloned().unwrap_or(Json::Null)).map_err(|e| e.to_string())
}

impl<K: BlockKind> BlockGraph<K> {
    /// Runs one canvas command whose arguments name a `@reporter-branch:`
    /// strand. Call it on a clone and keep the clone only on `Ok`.
    pub fn edit_reporter_branch(
        &mut self,
        cmd: &str,
        args: &Json,
        codec: &BranchCodec<'_, K>,
    ) -> Result<Json, String> {
        let ids = reporter_branch_ids(args, CANVAS_ARG_KEYS);
        let open = self.open_reporter_branches(&ids, codec.read)?;
        let strand = || arg::<String>(args, "strandId");
        let path = || arg::<Vec<PathStep>>(args, "path");
        let edit = |graph: &mut Self, command| {
            graph
                .apply_edit(command, &EditContext::default())
                .map(|_| Json::Null)
                .map_err(String::from)
        };
        let result = match cmd {
            "add_instruction" => {
                let instruction = (codec.instruction)(&args["instruction"])?;
                let command = EditCommand::InsertInstruction {
                    strand_id: strand()?,
                    path: path()?,
                    instruction,
                };
                edit(self, command)?
            }
            "edit_instruction" => {
                let instruction = (codec.instruction)(&args["instruction"])?;
                if !self.replace_instruction(&strand()?, &path()?, instruction) {
                    return Err("Instruction is missing".into());
                }
                Json::Null
            }
            "merge_strand" => {
                let dragged = arg::<String>(args, "draggedId")?;
                self.merge_strand(&dragged, &arg::<String>(args, "targetId")?, &path()?)?;
                Json::Null
            }
            "merge_tail" => {
                let target = arg::<String>(args, "targetId")?;
                let target_path = arg::<Vec<PathStep>>(args, "targetPath")?;
                self.merge_tail(&strand()?, &path()?, &target, &target_path)?;
                Json::Null
            }
            "split_strand" => {
                json!(self.split_strand(&strand()?, &path()?, arg(args, "x")?, arg(args, "y")?)?)
            }
            "move_strand" => json!(self.split_strand(
                &strand()?,
                &[PathStep::at(0)],
                arg(args, "x")?,
                arg(args, "y")?
            )?),
            "remove_strand" => {
                let id = strand()?;
                self.strands.retain(|s| s.id != id);
                Json::Null
            }
            "remove_instruction" => {
                let command = EditCommand::RemoveInstructions {
                    strand_id: strand()?,
                    path: path()?,
                    count: arg::<Option<usize>>(args, "count")?.unwrap_or(1),
                };
                edit(self, command)?
            }
            "duplicate_instruction" => {
                let command = EditCommand::DuplicateInstruction {
                    strand_id: strand()?,
                    path: path()?,
                };
                edit(self, command)?
            }
            "copy_instructions" => {
                let fragment = self
                    .copy_fragment(&strand()?, &path()?, arg(args, "count")?)
                    .map_err(String::from)?;
                (codec.fragment)(&fragment)?
            }
            "edit_value_field" => {
                let command = EditCommand::EditFieldText {
                    location: arg(args, "location")?,
                    text: arg(args, "text")?,
                };
                edit(self, command)?
            }
            "put_value" => {
                if !self.put_value(&arg(args, "location")?, arg(args, "value")?) {
                    return Err("Value slot is missing".into());
                }
                Json::Null
            }
            "take_value" => serde_json::to_value(self.take_value(&arg(args, "location")?))
                .map_err(|e| e.to_string())?,
            "move_value" => {
                let to = arg::<Option<ValueLocation>>(args, "to")?
                    .map(ValueDestination::Slot)
                    .unwrap_or(ValueDestination::Canvas {
                        x: arg::<Option<i32>>(args, "x")?.unwrap_or(0),
                        y: arg::<Option<i32>>(args, "y")?.unwrap_or(0),
                        origin_block_id: arg(args, "originBlockId")?,
                    });
                let command = EditCommand::MoveValue {
                    from: arg(args, "from")?,
                    to,
                };
                edit(self, command)?
            }
            _ => {
                return Err(format!(
                    "Command '{cmd}' is unavailable inside a reporter branch"
                ));
            }
        };
        // A stack dropped on another's top takes the dragged one's place.
        if matches!(cmd, "merge_strand" | "merge_tail")
            && let Some(y) = arg::<Option<i32>>(args, "targetY")?
        {
            let key = if cmd == "merge_tail" {
                "targetPath"
            } else {
                "path"
            };
            let target_path = arg::<Vec<PathStep>>(args, key)?;
            if target_path.len() == 1
                && target_path[0].index == 0
                && let Some(target) = self.strand_mut(&arg::<String>(args, "targetId")?)
            {
                target.y = y;
            }
        }
        self.close_reporter_branches(open, codec.write)?;
        Ok(result)
    }
}
