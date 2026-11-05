//! The value system: the recursive expression tree behind every numeric,
//! text and boolean slot on the canvas, plus its evaluation.

mod descriptor;
mod eval;
mod ops;
mod wire;

pub use descriptor::{
    ArgDescriptor, NameSource, OperatorDescriptor, ValueType, builtin_operator_descriptors,
    host_operator_descriptors, operator_descriptor, operator_descriptors, render_descriptors_qml,
    replace_generated,
};
pub use ops::{
    BUILTIN_OPERATOR_KINDS, ExtOperator, Op, OperatorKind, OperatorKindSpec, ext_operator,
    operator_kind, register_operators,
};

use serde::{Deserialize, Deserializer, Serialize};
use std::collections::HashMap;

/// Recursive expression tree behind a value slot: a number, text, or an
/// operator over nested `args`. `saved` holds whatever an operator displaced
/// when it took the slot, so dragging it back out restores it.
#[derive(Debug, Clone, PartialEq, Serialize)]
#[serde(tag = "kind")]
pub enum Value {
    Number {
        value: f64,
    },
    Text {
        value: String,
    },
    /// The "nothing plugged in here" state of a boolean slot, evaluating as
    /// `false` like Scratch's empty hexagon. Distinct from the standalone
    /// `Op::True`/`Op::False` blocks, which are deliberate.
    Bool,
    Op {
        op: Op,
        args: Vec<Value>,
        saved: Box<Value>,
    },
    /// A read of a document-wide variable, resolved by
    /// [`Value::resolve_vars`] before `eval` sees it.
    Var {
        name: String,
    },
    /// A read of the current custom-block invocation's bound parameter -
    /// its own scope, so concurrent invocations don't share a slot.
    Param {
        name: String,
    },
    /// Value-position call of a reporter-shaped custom block. Same shape as
    /// `Op`, and resolved by the host's interpreter before `eval`.
    Call {
        block_id: String,
        args: Vec<Value>,
        #[serde(default)]
        branches: Vec<Vec<serde_json::Value>>,
        saved: Box<Value>,
    },
}

/// Result of evaluating a [`Value`] - also how a variable's current value
/// is persisted, hence the extra derives.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(tag = "kind", content = "value")]
pub enum Evaluated {
    Number(f64),
    Text(String),
    Bool(bool),
}

/// Manual impl mirroring `Value`'s own - `f64` isn't `Hash`, so its bit
/// pattern stands in.
impl std::hash::Hash for Evaluated {
    fn hash<H: std::hash::Hasher>(&self, state: &mut H) {
        match self {
            Evaluated::Number(n) => {
                0u8.hash(state);
                n.to_bits().hash(state);
            }
            Evaluated::Text(s) => {
                1u8.hash(state);
                s.hash(state);
            }
            Evaluated::Bool(b) => {
                2u8.hash(state);
                b.hash(state);
            }
        }
    }
}

impl Evaluated {
    /// Coerces to a number, parsing text loosely (so a `Text` leaf like
    /// `"5"` still works as an operand); errs with a readable message otherwise.
    pub fn as_number(&self) -> Result<f64, String> {
        match self {
            Evaluated::Number(n) => Ok(*n),
            Evaluated::Text(s) => s
                .trim()
                .parse::<f64>()
                .map_err(|_| format!("\"{s}\" is not a number")),
            Evaluated::Bool(b) => Ok(if *b { 1.0 } else { 0.0 }),
        }
    }

    /// Coerces to a boolean, always succeeding: a nonzero number or a
    /// nonempty, non-`"false"` string counts as true.
    pub fn as_bool(&self) -> bool {
        match self {
            Evaluated::Bool(b) => *b,
            Evaluated::Number(n) => *n != 0.0,
            Evaluated::Text(s) => !s.is_empty() && s != "false",
        }
    }

    /// Stringifies for display/comparison - like `eval_text`, but from an
    /// already-evaluated result (no re-evaluation).
    pub fn as_text(&self) -> String {
        match self {
            Evaluated::Text(s) => s.clone(),
            Evaluated::Number(n) => n.to_string(),
            Evaluated::Bool(b) => b.to_string(),
        }
    }

    /// Rebuilds a `Value` leaf holding this result - `Bool` becomes a
    /// `True`/`False` op node, since there's no bare boolean `Value` leaf.
    pub fn into_value(self) -> Value {
        match self {
            Evaluated::Number(value) => Value::Number { value },
            Evaluated::Text(value) => Value::Text { value },
            Evaluated::Bool(b) => Value::Op {
                op: if b { Op::True } else { Op::False },
                args: vec![],
                saved: Box::new(Value::number(0.0)),
            },
        }
    }
}

impl Value {
    pub fn number(value: f64) -> Self {
        Value::Number { value }
    }

    pub fn text(value: impl Into<String>) -> Self {
        Value::Text {
            value: value.into(),
        }
    }

    /// Builds an operator node over `args`, with a plain zero as the
    /// displaced `saved` value.
    pub fn op(op: Op, args: Vec<Value>) -> Self {
        Value::Op {
            op,
            args,
            saved: Box::new(Value::number(0.0)),
        }
    }

    /// Read-only counterpart to [`Value::get_mut`].
    pub fn get(&self, path: &[u8]) -> Option<&Value> {
        match path.split_first() {
            None => Some(self),
            Some((&step, rest)) => match self {
                Value::Op { args, .. } | Value::Call { args, .. } => {
                    args.get(step as usize)?.get(rest)
                }
                _ => None,
            },
        }
    }

    /// Walks `path` (`n` steps into `args[n]` at each `Op`) down to the
    /// addressed node; an empty path returns `self`.
    pub fn get_mut(&mut self, path: &[u8]) -> Option<&mut Value> {
        match path.split_first() {
            None => Some(self),
            Some((&step, rest)) => match self {
                Value::Op { args, .. } | Value::Call { args, .. } => {
                    args.get_mut(step as usize)?.get_mut(rest)
                }
                _ => None,
            },
        }
    }

    /// The value this node is shadowing - what a slot restores to when this
    /// node is dragged back out of it.
    pub fn saved(&self) -> Option<&Value> {
        match self {
            Value::Op { saved, .. } | Value::Call { saved, .. } => Some(saved),
            _ => None,
        }
    }

    /// Renames every `Value::Var` leaf reading `old` (including in `saved`)
    /// to `new`, so existing blocks keep working after a variable rename.
    pub fn rename_var(&mut self, old: &str, new: &str) {
        match self {
            Value::Var { name } => {
                if name == old {
                    *name = new.to_string();
                }
            }
            Value::Op { args, saved, .. } | Value::Call { args, saved, .. } => {
                for arg in args.iter_mut() {
                    arg.rename_var(old, new);
                }
                saved.rename_var(old, new);
            }
            Value::Number { .. } | Value::Text { .. } | Value::Bool | Value::Param { .. } => {}
        }
    }

    /// Renames every `Value::Param` leaf reading `old` to `new` (including in
    /// `saved`) - counterpart to `rename_var`, for when a block input is renamed.
    pub fn rename_param(&mut self, old: &str, new: &str) {
        match self {
            Value::Param { name } => {
                if name == old {
                    *name = new.to_string();
                }
            }
            Value::Op { args, saved, .. } | Value::Call { args, saved, .. } => {
                for arg in args.iter_mut() {
                    arg.rename_param(old, new);
                }
                saved.rename_param(old, new);
            }
            Value::Number { .. } | Value::Text { .. } | Value::Bool | Value::Var { .. } => {}
        }
    }

    /// Applies `f` to the branch bodies of every call of `block_id` in this
    /// tree, like [`Value::for_each_call_args_mut`].
    pub fn for_each_call_branches_mut(
        &mut self,
        block_id: &str,
        f: &mut dyn FnMut(&mut Vec<Vec<serde_json::Value>>),
    ) {
        match self {
            Value::Number { .. }
            | Value::Text { .. }
            | Value::Bool
            | Value::Var { .. }
            | Value::Param { .. } => {}
            Value::Op { args, saved, .. } => {
                for a in args.iter_mut() {
                    a.for_each_call_branches_mut(block_id, f);
                }
                saved.for_each_call_branches_mut(block_id, f);
            }
            Value::Call {
                block_id: id,
                args,
                branches,
                saved,
            } => {
                if id == block_id {
                    f(branches);
                }
                for a in args.iter_mut() {
                    a.for_each_call_branches_mut(block_id, f);
                }
                saved.for_each_call_branches_mut(block_id, f);
            }
        }
    }

    /// Applies `f` to the `args` of every `Value::Call` on `block_id`, so
    /// call sites stay aligned with the block's current pieces.
    pub fn for_each_call_args_mut(&mut self, block_id: &str, f: &mut dyn FnMut(&mut Vec<Value>)) {
        match self {
            Value::Number { .. }
            | Value::Text { .. }
            | Value::Bool
            | Value::Var { .. }
            | Value::Param { .. } => {}
            Value::Op { args, saved, .. } => {
                for a in args.iter_mut() {
                    a.for_each_call_args_mut(block_id, f);
                }
                saved.for_each_call_args_mut(block_id, f);
            }
            Value::Call {
                block_id: id,
                args,
                saved,
                ..
            } => {
                if id == block_id {
                    f(args);
                }
                for a in args.iter_mut() {
                    a.for_each_call_args_mut(block_id, f);
                }
                saved.for_each_call_args_mut(block_id, f);
            }
        }
    }

    /// Every custom block id a `Value::Call` in this tree names.
    pub fn visit_block_calls(&self, f: &mut dyn FnMut(&str)) {
        match self {
            Value::Number { .. }
            | Value::Text { .. }
            | Value::Bool
            | Value::Var { .. }
            | Value::Param { .. } => {}
            Value::Op { args, saved, .. } => {
                for arg in args {
                    arg.visit_block_calls(f);
                }
                saved.visit_block_calls(f);
            }
            Value::Call {
                block_id,
                args,
                saved,
                ..
            } => {
                f(block_id);
                for arg in args {
                    arg.visit_block_calls(f);
                }
                saved.visit_block_calls(f);
            }
        }
    }

    /// Replaces every `Value::Call` on `block_id` with a plain `0` leaf, so
    /// deleting a block leaves no dangling reference.
    pub fn scrub_block_calls(&mut self, block_id: &str) {
        match self {
            Value::Number { .. }
            | Value::Text { .. }
            | Value::Bool
            | Value::Var { .. }
            | Value::Param { .. } => {}
            Value::Op { args, saved, .. } => {
                for a in args.iter_mut() {
                    a.scrub_block_calls(block_id);
                }
                saved.scrub_block_calls(block_id);
            }
            Value::Call {
                block_id: id,
                args,
                saved,
                ..
            } => {
                if id == block_id {
                    *self = Value::number(0.0);
                } else {
                    for a in args.iter_mut() {
                        a.scrub_block_calls(block_id);
                    }
                    saved.scrub_block_calls(block_id);
                }
            }
        }
    }

    /// Repairs a boolean slot poisoned by a legacy blank, where an empty one
    /// was a `False` op whose `saved` was a plain `Number(0)`. The caller
    /// marks its own boolean slots; this threads that into nested operands.
    pub fn migrate_bool_slots(&mut self, expects_bool: bool) {
        if expects_bool && matches!(self, Value::Number { .. }) {
            *self = Value::Bool;
            return;
        }
        match self {
            Value::Op { op, args, saved } => {
                let args_are_bool = matches!(op, Op::And | Op::Or | Op::Not);
                for arg in args.iter_mut() {
                    arg.migrate_bool_slots(args_are_bool);
                }
                saved.migrate_bool_slots(expects_bool);
            }
            Value::Call { args, saved, .. } => {
                for arg in args.iter_mut() {
                    arg.migrate_bool_slots(false);
                }
                saved.migrate_bool_slots(expects_bool);
            }
            Value::Number { .. }
            | Value::Text { .. }
            | Value::Bool
            | Value::Var { .. }
            | Value::Param { .. } => {}
        }
    }

    /// Rebuilds the tree with every `Value::Var` replaced by its value from
    /// `env`, defaulting to `0`. Must run before `eval`.
    pub fn resolve_vars(&self, env: &HashMap<String, Evaluated>) -> Value {
        match self {
            Value::Number { value } => Value::Number { value: *value },
            Value::Text { value } => Value::Text {
                value: value.clone(),
            },
            Value::Bool => Value::Bool,
            Value::Op { op, args, saved } => Value::Op {
                op: op.clone(),
                args: args.iter().map(|a| a.resolve_vars(env)).collect(),
                saved: Box::new(saved.resolve_vars(env)),
            },
            Value::Var { name } => match env.get(name) {
                Some(e) => e.clone().into_value(),
                None => Value::number(0.0),
            },
            // Left alone: `Param`/`Call` need execution this module can't
            // do. Only their nested `args` may hold `Var` reads.
            Value::Param { name } => Value::Param { name: name.clone() },
            Value::Call {
                block_id,
                args,
                branches,
                saved,
            } => Value::Call {
                block_id: block_id.clone(),
                args: args.iter().map(|a| a.resolve_vars(env)).collect(),
                branches: branches.clone(),
                saved: Box::new(saved.resolve_vars(env)),
            },
        }
    }
}

#[cfg(test)]
mod tests;
