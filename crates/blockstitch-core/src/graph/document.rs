//! [`BlockGraph`] - everything one canvas holds, and the structural
//! operations over it.

use crate::graph::block::{BlockDef, BlockPiece, BlockShape, InputValueType};
use crate::graph::canvas::{Comment, FloatingValue, Strand, VariableDef};
use crate::graph::instruction::{BlockKind, Instruction};
use crate::graph::new_id;
use crate::value::{Evaluated, Value};
use serde::{Deserialize, Serialize};
use std::collections::{HashMap, HashSet};

/// One block-editor canvas: its instruction stacks, the value blocks and
/// notes parked around them, its variables, and its custom blocks. A host's
/// own document type owns one rather than re-declaring the five collections;
/// `#[serde(flatten)]` on that field keeps the wire format flat.
#[derive(Debug, Clone, PartialEq, Hash, Serialize, Deserialize)]
#[serde(bound(serialize = "K: Serialize", deserialize = "K: Deserialize<'de>"))]
pub struct BlockGraph<K> {
    #[serde(default = "Vec::new")]
    pub strands: Vec<Strand<K>>,
    /// Value blocks parked on open canvas - see [`FloatingValue`].
    #[serde(default)]
    pub floating_values: Vec<FloatingValue>,
    /// Floating/attached notes - see [`Comment`].
    #[serde(default)]
    pub comments: Vec<Comment>,
    /// User-declared document-wide variables - see [`VariableDef`].
    #[serde(default)]
    pub variables: Vec<VariableDef>,
    /// User-defined custom blocks - see [`BlockDef`]. Each def's body lives
    /// in its own header strand within `strands`.
    #[serde(default)]
    pub block_defs: Vec<BlockDef>,
}

impl<K> Default for BlockGraph<K> {
    fn default() -> Self {
        Self {
            strands: Vec::new(),
            floating_values: Vec::new(),
            comments: Vec::new(),
            variables: Vec::new(),
            block_defs: Vec::new(),
        }
    }
}

impl<K> BlockGraph<K> {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn strand(&self, id: &str) -> Option<&Strand<K>> {
        self.strands.iter().find(|s| s.id == id)
    }

    pub fn strand_mut(&mut self, id: &str) -> Option<&mut Strand<K>> {
        self.strands.iter_mut().find(|s| s.id == id)
    }

    pub fn floating_value(&self, id: &str) -> Option<&FloatingValue> {
        self.floating_values.iter().find(|f| f.id == id)
    }

    pub fn floating_value_mut(&mut self, id: &str) -> Option<&mut FloatingValue> {
        self.floating_values.iter_mut().find(|f| f.id == id)
    }

    pub fn comment_mut(&mut self, id: &str) -> Option<&mut Comment> {
        self.comments.iter_mut().find(|c| c.id == id)
    }

    pub fn block_def(&self, id: &str) -> Option<&BlockDef> {
        self.block_defs.iter().find(|b| b.id == id)
    }

    pub fn block_def_mut(&mut self, id: &str) -> Option<&mut BlockDef> {
        self.block_defs.iter_mut().find(|b| b.id == id)
    }

    /// Writes live runtime variable values back into `variables` - called
    /// before the document is saved, once a run finishes.
    pub fn sync_variables_from(&mut self, values: &HashMap<String, Evaluated>) {
        for var in &mut self.variables {
            if let Some(v) = values.get(&var.name) {
                var.value = v.clone();
            }
        }
    }

    /// Declared variables and their persisted values, as the runtime store
    /// wants them.
    pub fn variable_values(&self) -> HashMap<String, Evaluated> {
        self.variables
            .iter()
            .map(|v| (v.name.clone(), v.value.clone()))
            .collect()
    }

    /// Declares a variable starting at `0`, returning its trimmed name.
    pub fn create_variable(&mut self, name: &str) -> Result<String, String> {
        let trimmed = name.trim().to_string();
        if trimmed.is_empty() {
            return Err("Variable name can't be empty".to_string());
        }
        if self.variables.iter().any(|v| v.name == trimmed) {
            return Err(format!("A variable named \"{trimmed}\" already exists"));
        }
        self.variables.push(VariableDef {
            name: trimmed.clone(),
            value: Evaluated::Number(0.0),
        });
        Ok(trimmed)
    }

    /// Removes `name` from the declared variables. Existing references are
    /// left in place - `Value::resolve_vars` defaults an unknown name to `0`.
    pub fn remove_variable(&mut self, name: &str) {
        self.variables.retain(|v| v.name != name);
    }
}

impl<K: BlockKind> BlockGraph<K> {
    /// Every instruction on the canvas, nested ones included.
    pub fn walk_instructions(&self, f: &mut dyn FnMut(&Instruction<K>)) {
        for strand in &self.strands {
            for ins in &strand.instructions {
                ins.walk(&mut *f);
            }
        }
    }

    /// Mutable counterpart to [`BlockGraph::walk_instructions`].
    pub fn walk_instructions_mut(&mut self, f: &mut dyn FnMut(&mut Instruction<K>)) {
        for strand in &mut self.strands {
            for ins in &mut strand.instructions {
                ins.walk_mut(&mut *f);
            }
        }
    }

    /// Every value anywhere in the document - inside instructions (nested
    /// ones included) and parked on open canvas.
    pub fn visit_values_mut(&mut self, f: &mut dyn FnMut(&mut Value, InputValueType)) {
        self.walk_instructions_mut(&mut |ins| ins.kind.visit_values_mut(&mut *f));
        for floating in &mut self.floating_values {
            f(&mut floating.value, InputValueType::Any);
        }
    }

    /// The strand holding `block_id`'s body.
    pub fn block_body(&self, block_id: &str) -> Option<&Strand<K>> {
        self.strands
            .iter()
            .find(|s| s.block_header_id() == Some(block_id))
    }

    /// Every instruction id reachable from any strand, nested ones included
    /// - the "still alive" set comment attachments are checked against.
    pub fn instruction_ids(&self) -> HashSet<String> {
        let mut out = HashSet::new();
        self.walk_instructions(&mut |ins| {
            out.insert(ins.id.clone());
        });
        out
    }

    /// Drops any comment attached to an instruction that no longer exists.
    /// Call after any mutation that can remove instructions or strands.
    pub fn prune_orphaned_comments(&mut self) {
        let live = self.instruction_ids();
        self.comments
            .retain(|c| c.attached_to.as_deref().is_none_or(|id| live.contains(id)));
    }

    /// Renames a declared variable and every reference to it, returning the
    /// trimmed name. Renaming to its own current name is a no-op success.
    pub fn rename_variable(&mut self, old: &str, new: &str) -> Result<String, String> {
        let trimmed = new.trim().to_string();
        if trimmed.is_empty() {
            return Err("Variable name can't be empty".to_string());
        }
        if trimmed != old && self.variables.iter().any(|v| v.name == trimmed) {
            return Err(format!("A variable named \"{trimmed}\" already exists"));
        }
        let Some(var) = self.variables.iter_mut().find(|v| v.name == old) else {
            return Err("Variable not found".to_string());
        };
        if trimmed == old {
            return Ok(trimmed);
        }
        var.name = trimmed.clone();
        let new = trimmed.as_str();
        for strand in &mut self.strands {
            for ins in &mut strand.instructions {
                ins.rename_var(old, new);
            }
        }
        for floating in &mut self.floating_values {
            floating.value.rename_var(old, new);
        }
        Ok(trimmed)
    }

    /// Defines a custom block: the [`BlockDef`] plus its empty body strand
    /// at `(x, y)`, headed by `header`. Caller validates `pieces` first.
    pub fn create_block(
        &mut self,
        pieces: Vec<BlockPiece>,
        shape: BlockShape,
        color: String,
        x: i32,
        y: i32,
        header: impl FnOnce(&str) -> K,
    ) -> String {
        let id = new_id();
        self.block_defs.push(BlockDef {
            id: id.clone(),
            pieces,
            shape,
            color,
        });
        let header = Instruction::new(header(&id));
        self.strands
            .push(Strand::with_instructions(x, y, vec![header]));
        id
    }

    /// Renames `Value::Param` reads within `block_id`'s own body. The
    /// caller still updates [`BlockDef::pieces`] separately.
    pub fn rename_block_input_body(&mut self, block_id: &str, old: &str, new: &str) {
        for strand in &mut self.strands {
            if strand.block_header_id() == Some(block_id) {
                for ins in &mut strand.instructions {
                    ins.rename_param(old, new);
                }
            }
        }
    }

    /// Rebuilds every call site's `args` for `new_pieces`, carrying values
    /// over by [`BlockPiece::id`] so a rename keeps them; new inputs get the
    /// blank their type asks for. Call before overwriting the pieces.
    pub fn reconcile_block_call_args(
        &mut self,
        block_id: &str,
        old_pieces: &[BlockPiece],
        new_pieces: &[BlockPiece],
    ) {
        let old_input_ids: Vec<&str> = old_pieces
            .iter()
            .filter(|p| matches!(p, BlockPiece::Input { .. }))
            .map(BlockPiece::id)
            .collect();
        let new_inputs: Vec<(&str, InputValueType)> = new_pieces
            .iter()
            .filter_map(|p| match p {
                BlockPiece::Input { id, value_type, .. } => Some((id.as_str(), *value_type)),
                BlockPiece::Label { .. } | BlockPiece::Branch { .. } => None,
            })
            .collect();
        // For each new input slot, which old slot (if any) it carries over from.
        let mapping: Vec<(Option<usize>, InputValueType)> = new_inputs
            .iter()
            .map(|(id, value_type)| (old_input_ids.iter().position(|old| old == id), *value_type))
            .collect();

        let mut rebuild = |args: &mut Vec<Value>| {
            *args = mapping
                .iter()
                .map(|(old_idx, value_type)| {
                    old_idx
                        .and_then(|i| args.get(i).cloned())
                        .unwrap_or_else(|| blank_for(*value_type))
                })
                .collect();
        };
        for strand in &mut self.strands {
            for ins in &mut strand.instructions {
                ins.for_each_call_args_mut(block_id, &mut rebuild);
            }
        }
        for floating in &mut self.floating_values {
            floating
                .value
                .for_each_call_args_mut(block_id, &mut rebuild);
        }
    }

    /// Deletes a custom block: its [`BlockDef`], its body strand, and every
    /// call of it, so no reference is left dangling.
    pub fn remove_block(&mut self, block_id: &str) {
        self.block_defs.retain(|b| b.id != block_id);
        self.strands
            .retain(|s| s.block_header_id() != Some(block_id));
        for strand in &mut self.strands {
            strand
                .instructions
                .retain(|ins| !ins.kind.calls_block(block_id));
            for ins in &mut strand.instructions {
                ins.scrub_block_calls(block_id);
            }
        }
        for floating in &mut self.floating_values {
            floating.value.scrub_block_calls(block_id);
        }
        self.prune_orphaned_comments();
    }

    /// Repairs boolean slots poisoned by a legacy blank, once per load. A
    /// custom block's call sites need [`BlockDef`] lookups the instruction
    /// can't do itself, so they're handled here rather than per-kind.
    pub fn migrate_bool_slots(&mut self) {
        for strand in &mut self.strands {
            for ins in &mut strand.instructions {
                ins.migrate_bool_slots();
            }
        }
        for floating in &mut self.floating_values {
            floating.value.migrate_bool_slots(false);
        }

        let boolean_inputs: Vec<(String, Vec<bool>)> = self
            .block_defs
            .iter()
            .map(|def| {
                let types = def
                    .input_types()
                    .map(|t| t == InputValueType::Bool)
                    .collect();
                (def.id.clone(), types)
            })
            .collect();
        for (block_id, expected) in boolean_inputs {
            let mut repair = |args: &mut Vec<Value>| {
                for (arg, expects_bool) in args.iter_mut().zip(&expected) {
                    if *expects_bool {
                        arg.migrate_bool_slots(true);
                    }
                }
            };
            for strand in &mut self.strands {
                for ins in &mut strand.instructions {
                    ins.for_each_call_args_mut(&block_id, &mut repair);
                }
            }
            for floating in &mut self.floating_values {
                floating
                    .value
                    .for_each_call_args_mut(&block_id, &mut repair);
            }
        }
    }

    /// Canonicalizes every persisted block color, so a hand-edited or
    /// imported document can't hand the frontend an unsafe CSS value.
    pub fn normalize_block_colors(&mut self) {
        for def in &mut self.block_defs {
            def.color = crate::graph::normalize_block_color(&def.color)
                .unwrap_or_else(crate::graph::default_block_color);
        }
    }
}

/// The blank a slot of this declared type restores to.
pub(crate) fn blank_for(value_type: InputValueType) -> Value {
    match value_type {
        InputValueType::Any => Value::number(0.0),
        InputValueType::Bool => Value::Bool,
    }
}
