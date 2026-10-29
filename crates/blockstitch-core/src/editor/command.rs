//! Typed edits with explicit outcomes: one gesture is one [`EditCommand`],
//! validated by [`BlockGraph::prepare_edit`] without writing anything, then
//! applied by [`BlockGraph::commit_edit`]. The host checkpoints in between,
//! only for an edit that changes something, and saves and notifies after.

use crate::editor::history::EditSession;
use crate::editor::location::{
    ValueBuffers, ValueLocation, drop_strand_buffers, prune_value_buffers,
};
use crate::editor::path::{InstrPath, PathStep, resolve_body};
use crate::graph::{BlockGraph, BlockKind, Comment, Fragment, IdMap, Instruction};
use crate::value::Value;
use serde::{Deserialize, Serialize};
use std::fmt;

/// One user gesture, as the canvas means it.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum EditCommand<K> {
    /// Drag a value block out of `from` into a slot or onto open canvas.
    MoveValue {
        from: ValueLocation,
        to: ValueDestination,
    },
    /// Text typed into a value slot.
    EditFieldText {
        location: ValueLocation,
        text: String,
    },
    /// Delete `count` instructions starting at `path` - a dragged tail
    /// dropped on the trash. `0` counts as `1`.
    RemoveInstructions {
        strand_id: String,
        path: InstrPath,
        count: usize,
    },
    InsertInstruction {
        strand_id: String,
        path: InstrPath,
        instruction: Instruction<K>,
    },
    /// A copied fragment dropped as a new strand at `(x, y)`, with fresh
    /// ids (see [`crate::graph::Fragment`] for the policy).
    PasteFragment {
        fragment: Fragment<K>,
        x: i32,
        y: i32,
    },
    /// A copy of the instruction at `path`, its bodies and its notes,
    /// inserted right after it.
    DuplicateInstruction { strand_id: String, path: InstrPath },
}

/// Where a moved value lands.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ValueDestination {
    Slot(ValueLocation),
    Canvas {
        x: i32,
        y: i32,
        #[serde(default)]
        origin_block_id: Option<String>,
    },
}

/// How a parsed number typed into a numeric slot is stored. Named policy,
/// since the two hosts have always differed here.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum NumberSpelling {
    /// Always as a number: `09` becomes `9`.
    #[default]
    Canonical,
    /// In an operator argument, text whose canonical spelling differs
    /// (`09`, `1.50`) is kept as text; top-level slots store the number.
    KeepTypedInOperands,
}

/// Host policy an edit needs to know about.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct EditContext {
    pub numbers: NumberSpelling,
}

/// Why an edit was refused. Nothing was written.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum EditError {
    /// A strand, path or location doesn't resolve.
    Missing(&'static str),
    /// It resolves, but the edit isn't allowed.
    Rejected(String),
}

impl fmt::Display for EditError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            EditError::Missing(what) => f.write_str(what),
            EditError::Rejected(why) => f.write_str(why),
        }
    }
}

impl std::error::Error for EditError {}

impl From<EditError> for String {
    fn from(e: EditError) -> Self {
        e.to_string()
    }
}

/// Something an edit made, by id.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Created {
    FloatingValue(String),
    Strand(String),
    Comment(String),
}

/// What the host should do to its [`ValueBuffers`].
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum BufferEffect {
    /// Show `text` at `location` instead of the stored value.
    Set {
        location: ValueLocation,
        text: String,
    },
    /// Forget `location` and everything under it.
    Prune(ValueLocation),
    /// Forget the strand's buffers - its instruction indices moved.
    DropStrand(String),
}

/// Applies an outcome's buffer effects in order.
pub fn apply_buffer_effects(buffers: &mut ValueBuffers, effects: &[BufferEffect]) {
    for effect in effects {
        match effect {
            BufferEffect::Set { location, text } => {
                buffers.insert(location.clone(), text.clone());
            }
            BufferEffect::Prune(location) => prune_value_buffers(buffers, location),
            BufferEffect::DropStrand(strand_id) => drop_strand_buffers(buffers, strand_id),
        }
    }
}

/// The result of a committed edit.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct EditOutcome {
    /// False for a valid no-op: no history, no save.
    pub changed: bool,
    pub created: Vec<Created>,
    pub buffers: Vec<BufferEffect>,
    /// Keystroke grouping key for [`crate::editor::History::checkpoint`].
    pub coalesce: Option<EditSession>,
    /// For a paste or duplicate: which instruction became which clone.
    pub ids: IdMap,
}

/// A validated edit, ready for [`BlockGraph::commit_edit`]. Commit it
/// against the same graph, under the same host lock it was prepared under.
#[derive(Debug, Clone)]
pub struct PreparedEdit<K> {
    plan: Plan<K>,
    buffers: Vec<BufferEffect>,
    coalesce: Option<EditSession>,
}

#[derive(Debug, Clone)]
enum Plan<K> {
    Nothing,
    MoveToSlot {
        from: ValueLocation,
        to: ValueLocation,
    },
    MoveToCanvas {
        from: ValueLocation,
        x: i32,
        y: i32,
        origin_block_id: Option<String>,
    },
    Reposition {
        floating_id: String,
        x: i32,
        y: i32,
    },
    WriteValue {
        location: ValueLocation,
        value: Value,
    },
    Remove {
        strand_id: String,
        path: InstrPath,
        count: usize,
    },
    Insert {
        strand_id: String,
        path: InstrPath,
        instruction: Instruction<K>,
    },
    /// Already cloned with fresh ids.
    Paste {
        fragment: Fragment<K>,
        ids: IdMap,
        x: i32,
        y: i32,
    },
    Duplicate {
        strand_id: String,
        path: InstrPath,
        instruction: Instruction<K>,
        comments: Vec<Comment>,
        ids: IdMap,
    },
}

impl<K> PreparedEdit<K> {
    /// Whether committing changes the graph. A host checkpoints only then.
    pub fn changes(&self) -> bool {
        !matches!(self.plan, Plan::Nothing)
    }

    pub fn coalesce(&self) -> Option<&EditSession> {
        self.coalesce.as_ref()
    }

    fn nothing(buffers: Vec<BufferEffect>, coalesce: Option<EditSession>) -> Self {
        Self {
            plan: Plan::Nothing,
            buffers,
            coalesce,
        }
    }
}

impl<K: BlockKind> BlockGraph<K> {
    /// A copy of the node `location` addresses. Field slots are reached
    /// through the host's mutable accessor, so this clones the instruction.
    pub fn value_at(&self, location: &ValueLocation) -> Option<Value> {
        match location {
            ValueLocation::Field {
                strand_id,
                index,
                field_id,
                path,
            } => {
                let mut kind = self.instruction_at(strand_id, index)?.kind.clone();
                kind.value_slot_mut(field_id)?.get(path).cloned()
            }
            ValueLocation::Floating { floating_id, path } => {
                self.floating_value(floating_id)?.value.get(path).cloned()
            }
        }
    }

    /// Validates `command` without writing anything.
    pub fn prepare_edit(
        &self,
        command: EditCommand<K>,
        context: &EditContext,
    ) -> Result<PreparedEdit<K>, EditError> {
        match command {
            EditCommand::MoveValue { from, to } => self.prepare_move(from, to),
            EditCommand::EditFieldText { location, text } => {
                self.prepare_text(location, text, context)
            }
            EditCommand::RemoveInstructions {
                strand_id,
                path,
                count,
            } => {
                let strand = self
                    .strand(&strand_id)
                    .ok_or(EditError::Missing("Unknown strand"))?;
                let (list, index) = resolve_body(&strand.instructions, &path)
                    .ok_or(EditError::Missing("Unknown instruction path"))?;
                if index >= list.len() {
                    return Err(EditError::Missing("Instruction index out of range"));
                }
                let count = count.max(1).min(list.len() - index);
                Ok(PreparedEdit {
                    buffers: vec![BufferEffect::DropStrand(strand_id.clone())],
                    plan: Plan::Remove {
                        strand_id,
                        path,
                        count,
                    },
                    coalesce: None,
                })
            }
            EditCommand::InsertInstruction {
                strand_id,
                path,
                instruction,
            } => {
                let strand = self
                    .strand(&strand_id)
                    .ok_or(EditError::Missing("Unknown strand"))?;
                resolve_body(&strand.instructions, &path)
                    .ok_or(EditError::Missing("Unknown instruction path"))?;
                self.check_header_placement(&strand_id, &path, &instruction)
                    .map_err(EditError::Rejected)?;
                Ok(PreparedEdit {
                    buffers: vec![BufferEffect::DropStrand(strand_id.clone())],
                    plan: Plan::Insert {
                        strand_id,
                        path,
                        instruction,
                    },
                    coalesce: None,
                })
            }
            EditCommand::PasteFragment { fragment, x, y } => {
                self.check_paste(&fragment)?;
                let (fragment, ids) = fragment.clone_fresh();
                Ok(PreparedEdit {
                    plan: Plan::Paste {
                        fragment,
                        ids,
                        x,
                        y,
                    },
                    buffers: Vec::new(),
                    coalesce: None,
                })
            }
            EditCommand::DuplicateInstruction { strand_id, path } => {
                let copied = self.copy_fragment(&strand_id, &path, Some(1))?;
                let (mut copy, ids) = copied.clone_fresh();
                let instruction = copy.instructions.remove(0);
                let mut next = path;
                if let Some(last) = next.last_mut() {
                    last.index += 1;
                }
                self.check_header_placement(&strand_id, &next, &instruction)
                    .map_err(EditError::Rejected)?;
                Ok(PreparedEdit {
                    buffers: vec![BufferEffect::DropStrand(strand_id.clone())],
                    plan: Plan::Duplicate {
                        strand_id,
                        path: next,
                        instruction,
                        comments: copy.comments,
                        ids,
                    },
                    coalesce: None,
                })
            }
        }
    }

    fn prepare_move(
        &self,
        from: ValueLocation,
        to: ValueDestination,
    ) -> Result<PreparedEdit<K>, EditError> {
        if matches!(self.value_at(&from), None | Some(Value::Bool)) {
            return Err(EditError::Missing("Nothing to take at that location"));
        }
        match to {
            ValueDestination::Slot(to) => {
                if self.value_at(&to).is_none() {
                    return Err(EditError::Missing("Unknown destination slot"));
                }
                if to == from {
                    return Ok(PreparedEdit::nothing(Vec::new(), None));
                }
                if from.same_root(&to) && to.path().starts_with(from.path()) {
                    return Err(EditError::Rejected(
                        "Can't drop a block inside itself".to_string(),
                    ));
                }
                Ok(PreparedEdit {
                    buffers: vec![
                        BufferEffect::Prune(from.clone()),
                        BufferEffect::Prune(to.clone()),
                    ],
                    plan: Plan::MoveToSlot { from, to },
                    coalesce: None,
                })
            }
            ValueDestination::Canvas {
                x,
                y,
                origin_block_id,
            } => {
                // A parked block moved on canvas keeps its id and origin.
                if let ValueLocation::Floating { floating_id, path } = &from
                    && path.is_empty()
                {
                    let floating = self
                        .floating_value(floating_id)
                        .ok_or(EditError::Missing("Nothing to take at that location"))?;
                    if (floating.x, floating.y) == (x, y) {
                        return Ok(PreparedEdit::nothing(Vec::new(), None));
                    }
                    return Ok(PreparedEdit {
                        plan: Plan::Reposition {
                            floating_id: floating_id.clone(),
                            x,
                            y,
                        },
                        buffers: Vec::new(),
                        coalesce: None,
                    });
                }
                Ok(PreparedEdit {
                    buffers: vec![BufferEffect::Prune(from.clone())],
                    plan: Plan::MoveToCanvas {
                        from,
                        x,
                        y,
                        origin_block_id,
                    },
                    coalesce: None,
                })
            }
        }
    }

    fn prepare_text(
        &self,
        location: ValueLocation,
        text: String,
        context: &EditContext,
    ) -> Result<PreparedEdit<K>, EditError> {
        let current = self
            .value_at(&location)
            .ok_or(EditError::Missing("Unknown value location"))?;
        let coalesce = Some(EditSession::Value(location.clone()));
        let (next, buffers) = if matches!(current, Value::Text { .. }) {
            (Some(Value::Text { value: text }), Vec::new())
        } else {
            let next = parse_number(
                &text,
                self.location_requires_integer(&location),
                !location.path().is_empty()
                    && context.numbers == NumberSpelling::KeepTypedInOperands,
            );
            let buffer = BufferEffect::Set {
                location: location.clone(),
                text,
            };
            (next, vec![buffer])
        };
        match next {
            Some(value) if value != current => Ok(PreparedEdit {
                plan: Plan::WriteValue { location, value },
                buffers,
                coalesce,
            }),
            _ => Ok(PreparedEdit::nothing(buffers, coalesce)),
        }
    }

    /// Applies a prepared edit. It can't fail on the graph it was prepared
    /// against.
    pub fn commit_edit(&mut self, prepared: PreparedEdit<K>) -> EditOutcome {
        let PreparedEdit {
            plan,
            buffers,
            coalesce,
        } = prepared;
        let mut created = Vec::new();
        let mut renamed = IdMap::new();
        let changed = match plan {
            Plan::Nothing => false,
            Plan::MoveToSlot { from, to } => match self.take_value(&from) {
                Some(value) => {
                    let put = self.put_value(&to, value);
                    debug_assert!(put, "destination vanished after validation");
                    true
                }
                None => false,
            },
            Plan::MoveToCanvas {
                from,
                x,
                y,
                origin_block_id,
            } => match self.take_value(&from) {
                Some(value) => {
                    let id = self.add_floating_value(x, y, value, origin_block_id);
                    created.push(Created::FloatingValue(id));
                    true
                }
                None => false,
            },
            Plan::Reposition { floating_id, x, y } => self.move_floating_value(&floating_id, x, y),
            Plan::WriteValue { location, value } => match self.value_at_mut(&location) {
                Some(node) => {
                    *node = value;
                    true
                }
                None => false,
            },
            Plan::Remove {
                strand_id,
                path,
                count,
            } => self.remove_run(&strand_id, &path, count),
            Plan::Insert {
                strand_id,
                path,
                instruction,
            } => self
                .insert_instruction(&strand_id, &path, instruction)
                .unwrap_or(false),
            Plan::Paste {
                fragment,
                ids,
                x,
                y,
            } => {
                let strand = self.add_strand(x, y, fragment.instructions);
                created.push(Created::Strand(strand));
                self.add_comments(fragment.comments, &mut created);
                renamed = ids;
                true
            }
            Plan::Duplicate {
                strand_id,
                path,
                instruction,
                comments,
                ids,
            } => {
                let inserted = self
                    .insert_instruction(&strand_id, &path, instruction)
                    .unwrap_or(false);
                if inserted {
                    self.add_comments(comments, &mut created);
                    renamed = ids;
                }
                inserted
            }
        };
        EditOutcome {
            changed,
            created,
            buffers,
            coalesce,
            ids: renamed,
        }
    }

    /// [`BlockGraph::prepare_edit`] then [`BlockGraph::commit_edit`], for a
    /// host that doesn't need to checkpoint in between.
    pub fn apply_edit(
        &mut self,
        command: EditCommand<K>,
        context: &EditContext,
    ) -> Result<EditOutcome, EditError> {
        let prepared = self.prepare_edit(command, context)?;
        Ok(self.commit_edit(prepared))
    }

    fn add_comments(&mut self, comments: Vec<Comment>, created: &mut Vec<Created>) {
        for comment in comments {
            created.push(Created::Comment(comment.id.clone()));
            self.comments.push(comment);
        }
    }

    /// Removes up to `count` instructions starting at `path` as one step.
    fn remove_run(&mut self, strand_id: &str, path: &[PathStep], count: usize) -> bool {
        let Some(strand) = self.strand_mut(strand_id) else {
            return false;
        };
        let Some((list, index)) =
            crate::editor::path::resolve_body_mut(&mut strand.instructions, path)
        else {
            return false;
        };
        if index >= list.len() {
            return false;
        }
        let end = (index + count.max(1)).min(list.len());
        list.drain(index..end);
        self.prune_orphaned_comments();
        true
    }
}

/// The value typed `text` stores in a numeric slot, or `None` while it
/// isn't a number yet (`-`, `1e`, `1.5` in an integer slot).
fn parse_number(text: &str, integer: bool, keep_spelling: bool) -> Option<Value> {
    let typed = text.trim();
    let number = if integer {
        typed.parse::<i32>().map(f64::from).ok()?
    } else {
        typed.parse::<f64>().ok()?
    };
    if keep_spelling && number.to_string() != typed {
        return Some(Value::text(typed));
    }
    Some(Value::number(number))
}
