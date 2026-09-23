//! The value system: the recursive expression tree behind every numeric,
//! text and boolean slot on the canvas, plus its evaluation.

mod ops;

pub use ops::{
    BUILTIN_OPERATOR_KINDS, ExtOperator, Op, OperatorKind, OperatorKindSpec, ext_operator,
    operator_kind, register_operators,
};

use rand::RngExt;
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

/// 1-based char index of the first occurrence of `needle` in `haystack`, or
/// `0` if not found/empty/too long. Scans by char, not byte, for multi-byte text.
fn char_index_of(haystack: &str, needle: &str) -> usize {
    let h: Vec<char> = haystack.chars().collect();
    let n: Vec<char> = needle.chars().collect();
    if n.is_empty() || n.len() > h.len() {
        return 0;
    }
    (0..=h.len() - n.len())
        .find(|&i| h[i..i + n.len()] == n[..])
        .map_or(0, |i| i + 1)
}

/// Same as [`char_index_of`], but the last occurrence.
fn char_last_index_of(haystack: &str, needle: &str) -> usize {
    let h: Vec<char> = haystack.chars().collect();
    let n: Vec<char> = needle.chars().collect();
    if n.is_empty() || n.len() > h.len() {
        return 0;
    }
    (0..=h.len() - n.len())
        .rev()
        .find(|&i| h[i..i + n.len()] == n[..])
        .map_or(0, |i| i + 1)
}

/// `Op::Eq`'s comparison rule: numeric if both sides parse as a number,
/// otherwise a text comparison (mirrors Scratch's loose `=`).
fn values_equal(l: &Evaluated, r: &Evaluated) -> bool {
    match (l.as_number(), r.as_number()) {
        (Ok(ln), Ok(rn)) => ln == rn,
        _ => l.as_text() == r.as_text(),
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

    pub fn eval(&self) -> Result<Evaluated, String> {
        match self {
            Value::Number { value } => Ok(Evaluated::Number(*value)),
            Value::Text { value } => Ok(Evaluated::Text(value.clone())),
            // The "nothing plugged in" state of a boolean slot acts as false.
            Value::Bool => Ok(Evaluated::Bool(false)),
            // `resolve_vars` runs first at every real call site; reaching
            // here means that step was skipped, which is a bug.
            Value::Var { .. } => Err("unresolved variable reference".to_string()),
            // Same invariant as `Var`: resolving these means executing
            // instructions, which this module can't do. It also keeps a
            // preview's best-effort eval safe - a call errors, never runs.
            Value::Param { .. } => Err("unresolved parameter reference".to_string()),
            Value::Call { .. } => Err("custom block calls can't be evaluated directly".to_string()),
            Value::Op {
                op: Op::Join, args, ..
            } => {
                let mut s = String::new();
                for a in args {
                    s.push_str(&a.eval_text()?);
                }
                Ok(Evaluated::Text(s))
            }
            Value::Op { op: Op::NewLine, .. } => Ok(Evaluated::Text("\n".to_string())),
            Value::Op { op: Op::Tab, .. } => Ok(Evaluated::Text("\t".to_string())),
            Value::Op {
                op: Op::Length,
                args,
                ..
            } => Ok(Evaluated::Number(
                args[0].eval_text()?.chars().count() as f64
            )),
            Value::Op {
                op: Op::IndexOf,
                args,
                ..
            } => {
                let needle = args[0].eval_text()?;
                let haystack = args[1].eval_text()?;
                Ok(Evaluated::Number(char_index_of(&haystack, &needle) as f64))
            }
            Value::Op {
                op: Op::LastIndexOf,
                args,
                ..
            } => {
                let needle = args[0].eval_text()?;
                let haystack = args[1].eval_text()?;
                Ok(Evaluated::Number(
                    char_last_index_of(&haystack, &needle) as f64
                ))
            }
            Value::Op {
                op: Op::LetterOf,
                args,
                ..
            } => {
                let index = args[0].eval_number()? as i64;
                let text = args[1].eval_text()?;
                let chars: Vec<char> = text.chars().collect();
                if index < 1 || index as usize > chars.len() {
                    return Err(format!(
                        "letter {index} is out of range for a {}-character value",
                        chars.len()
                    ));
                }
                Ok(Evaluated::Text(chars[index as usize - 1].to_string()))
            }
            Value::Op {
                op: Op::Case, args, ..
            } => {
                let text = args[0].eval_text()?;
                let upper = args[1].eval_text()? == "Upper";
                Ok(Evaluated::Text(if upper {
                    text.to_uppercase()
                } else {
                    text.to_lowercase()
                }))
            }
            Value::Op {
                op: Op::Round,
                args,
                ..
            } => Ok(Evaluated::Number(args[0].eval_number()?.round())),
            Value::Op {
                op: Op::Math, args, ..
            } => {
                let function = args[0].eval_text()?;
                let n = args[1].eval_number()?;
                let degrees_to_radians = std::f64::consts::PI / 180.0;
                let radians_to_degrees = 180.0 / std::f64::consts::PI;
                let result = match function.as_str() {
                    "Abs" => n.abs(),
                    "Floor" => n.floor(),
                    "Ceiling" => n.ceil(),
                    "Sign" => {
                        if n > 0.0 {
                            1.0
                        } else if n < 0.0 {
                            -1.0
                        } else {
                            0.0
                        }
                    }
                    "Sqrt" => n.sqrt(),
                    "Sin" => (n * degrees_to_radians).sin(),
                    "Cos" => (n * degrees_to_radians).cos(),
                    "Tan" => (n * degrees_to_radians).tan(),
                    "Asin" => n.asin() * radians_to_degrees,
                    "Acos" => n.acos() * radians_to_degrees,
                    "Atan" => n.atan() * radians_to_degrees,
                    "Ln" => n.ln(),
                    "Log" => n.log10(),
                    "Log2" => n.log2(),
                    "EPower" => n.exp(),
                    "TenPower" => 10.0_f64.powf(n),
                    other => return Err(format!("unknown math function '{other}'")),
                };
                Ok(Evaluated::Number(result))
            }
            Value::Op { op: Op::True, .. } => Ok(Evaluated::Bool(true)),
            Value::Op { op: Op::False, .. } => Ok(Evaluated::Bool(false)),
            Value::Op {
                op: Op::CurrentTime,
                args,
                ..
            } => {
                use chrono::{Datelike, Timelike};
                let now = chrono::Local::now();
                let n = match args[0].eval_text()?.as_str() {
                    "Year" => now.year() as f64,
                    "Month" => now.month() as f64,
                    "Date" => now.day() as f64,
                    // 1 (Sunday) through 7 (Saturday), matching Scratch's own
                    // "current (day of week)" numbering.
                    "DayOfWeek" => now.weekday().num_days_from_sunday() as f64 + 1.0,
                    "Hour" => now.hour() as f64,
                    "Minute" => now.minute() as f64,
                    "Second" => now.second() as f64,
                    other => return Err(format!("unknown current-time component '{other}'")),
                };
                Ok(Evaluated::Number(n))
            }
            Value::Op {
                op: Op::Not, args, ..
            } => Ok(Evaluated::Bool(!args[0].eval()?.as_bool())),
            Value::Op {
                op: Op::And, args, ..
            } => Ok(Evaluated::Bool(
                args[0].eval()?.as_bool() && args[1].eval()?.as_bool(),
            )),
            Value::Op {
                op: Op::Or, args, ..
            } => Ok(Evaluated::Bool(
                args[0].eval()?.as_bool() || args[1].eval()?.as_bool(),
            )),
            Value::Op {
                op: Op::Eq, args, ..
            } => Ok(Evaluated::Bool(values_equal(
                &args[0].eval()?,
                &args[1].eval()?,
            ))),
            Value::Op {
                op: Op::Neq, args, ..
            } => Ok(Evaluated::Bool(!values_equal(
                &args[0].eval()?,
                &args[1].eval()?,
            ))),
            Value::Op {
                op: Op::Gt, args, ..
            } => Ok(Evaluated::Bool(
                args[0].eval()?.as_number()? > args[1].eval()?.as_number()?,
            )),
            Value::Op {
                op: Op::Lt, args, ..
            } => Ok(Evaluated::Bool(
                args[0].eval()?.as_number()? < args[1].eval()?.as_number()?,
            )),
            Value::Op {
                op: Op::Gte, args, ..
            } => Ok(Evaluated::Bool(
                args[0].eval()?.as_number()? >= args[1].eval()?.as_number()?,
            )),
            Value::Op {
                op: Op::Lte, args, ..
            } => Ok(Evaluated::Bool(
                args[0].eval()?.as_number()? <= args[1].eval()?.as_number()?,
            )),
            // Host-registered operator: every arg is evaluated up front, so
            // an extension can't short-circuit the way `And`/`Or` do.
            Value::Op {
                op: Op::Ext(name),
                args,
                ..
            } => {
                let operator = ext_operator(name).ok_or_else(|| {
                    format!("unknown operator '{name}' - was the host's operator registry installed?")
                })?;
                let args = args
                    .iter()
                    .map(Value::eval)
                    .collect::<Result<Vec<_>, _>>()?;
                (operator.eval)(&args)
            }
            Value::Op { op, args, .. } => {
                let l = args[0].eval()?.as_number()?;
                let r = args[1].eval()?.as_number()?;
                let result = match op {
                    Op::Add => l + r,
                    Op::Sub => l - r,
                    Op::Mul => l * r,
                    Op::Div => {
                        if r == 0.0 {
                            return Err("division by zero".to_string());
                        }
                        l / r
                    }
                    Op::Mod => {
                        if r == 0.0 {
                            return Err("mod by zero".to_string());
                        }
                        l.rem_euclid(r)
                    }
                    Op::Random => {
                        let (lo, hi) = (l.min(r), l.max(r));
                        if l.fract() == 0.0 && r.fract() == 0.0 {
                            rand::rng().random_range(lo as i64..=hi as i64) as f64
                        } else {
                            rand::rng().random_range(lo..=hi)
                        }
                    }
                    other => unreachable!("{} matched above", other.name()),
                };
                Ok(Evaluated::Number(result))
            }
        }
    }

    /// Evaluates the tree and coerces the result to a number - the entry
    /// point every numeric instruction field actually calls.
    pub fn eval_number(&self) -> Result<f64, String> {
        self.eval()?.as_number()
    }

    /// Evaluates to a string - the entry point a text-typed field calls.
    /// Numeric results get stringified.
    pub fn eval_text(&self) -> Result<String, String> {
        Ok(self.eval()?.as_text())
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

/// Manual impl mirroring the host's own manual `Hash` impls - `f64` isn't
/// `Hash`, so its bit pattern stands in.
impl std::hash::Hash for Value {
    fn hash<H: std::hash::Hasher>(&self, state: &mut H) {
        match self {
            Value::Number { value } => {
                0u8.hash(state);
                value.to_bits().hash(state);
            }
            Value::Text { value } => {
                1u8.hash(state);
                value.hash(state);
            }
            Value::Bool => {
                6u8.hash(state);
            }
            Value::Op { op, args, saved } => {
                2u8.hash(state);
                op.hash(state);
                args.hash(state);
                saved.hash(state);
            }
            Value::Var { name } => {
                3u8.hash(state);
                name.hash(state);
            }
            Value::Param { name } => {
                4u8.hash(state);
                name.hash(state);
            }
            Value::Call {
                block_id,
                args,
                branches,
                saved,
            } => {
                5u8.hash(state);
                block_id.hash(state);
                args.hash(state);
                serde_json::to_string(branches).unwrap_or_default().hash(state);
                saved.hash(state);
            }
        }
    }
}

/// Accepts the tagged `{"kind": ...}` shape or a bare number/string, since
/// old save files have plain values in slots `Value` now occupies.
impl<'de> Deserialize<'de> for Value {
    fn deserialize<D>(deserializer: D) -> Result<Self, D::Error>
    where
        D: Deserializer<'de>,
    {
        fn default_saved() -> Box<Value> {
            Box::new(Value::number(0.0))
        }

        #[derive(Deserialize)]
        #[serde(tag = "kind")]
        enum Tagged {
            Number {
                value: f64,
            },
            Text {
                value: String,
            },
            Bool,
            Op {
                op: Op,
                args: Vec<Value>,
                // Older save files predate `saved` entirely - falls back to
                // a plain zero, same spirit as `ValueDe::Legacy` below.
                #[serde(default = "default_saved")]
                saved: Box<Value>,
            },
            Var {
                name: String,
            },
            Param {
                name: String,
            },
            Call {
                block_id: String,
                args: Vec<Value>,
                #[serde(default)]
                branches: Vec<Vec<serde_json::Value>>,
                #[serde(default = "default_saved")]
                saved: Box<Value>,
            },
            // Legacy tags predating the `BinaryOp`/`Join` → `Op` unification -
            // kept so old saves still load, migrated into `Value::Op` below.
            BinaryOp {
                op: Op,
                lhs: Box<Value>,
                rhs: Box<Value>,
                #[serde(default = "default_saved")]
                saved: Box<Value>,
            },
            Join {
                args: Vec<Value>,
                #[serde(default = "default_saved")]
                saved: Box<Value>,
            },
        }

        #[derive(Deserialize)]
        #[serde(untagged)]
        enum ValueDe {
            Legacy(f64),
            // Pre-`Value` shape of a text field - a bare JSON string, from
            // when it held a plain `String` rather than a tree.
            LegacyText(String),
            Current(Tagged),
        }

        Ok(match ValueDe::deserialize(deserializer)? {
            ValueDe::Legacy(n) => Value::Number { value: n },
            ValueDe::LegacyText(s) => Value::Text { value: s },
            ValueDe::Current(Tagged::Number { value }) => Value::Number { value },
            ValueDe::Current(Tagged::Text { value }) => Value::Text { value },
            ValueDe::Current(Tagged::Bool) => Value::Bool,
            ValueDe::Current(Tagged::Op { op, args, saved }) => Value::Op { op, args, saved },
            ValueDe::Current(Tagged::Var { name }) => Value::Var { name },
            ValueDe::Current(Tagged::Param { name }) => Value::Param { name },
            ValueDe::Current(Tagged::Call {
                block_id,
                args,
                branches,
                saved,
            }) => Value::Call {
                block_id,
                args,
                branches,
                saved,
            },
            ValueDe::Current(Tagged::BinaryOp {
                op,
                lhs,
                rhs,
                saved,
            }) => Value::Op {
                op,
                args: vec![*lhs, *rhs],
                saved,
            },
            ValueDe::Current(Tagged::Join { args, saved }) => Value::Op {
                op: Op::Join,
                args,
                saved,
            },
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn legacy_bare_number_deserializes_to_number() {
        let v: Value = serde_json::from_str("5.0").unwrap();
        assert_eq!(v, Value::number(5.0));
    }

    #[test]
    fn legacy_bare_string_deserializes_to_text() {
        // Pre-`Value` save shape of a text field, from back when it held a
        // plain `String` - must keep loading old documents.
        let v: Value = serde_json::from_str("\"hello\"").unwrap();
        assert_eq!(v, Value::text("hello"));
    }

    #[test]
    fn eval_text_passes_through_text_leaf() {
        assert_eq!(Value::text("hi").eval_text(), Ok("hi".to_string()));
    }

    #[test]
    fn eval_text_stringifies_numeric_result() {
        let v = Value::op(Op::Add, vec![Value::number(2.0), Value::number(3.0)]);
        assert_eq!(v.eval_text(), Ok("5".to_string()));
    }

    #[test]
    fn tagged_shape_round_trips() {
        let v = Value::op(Op::Add, vec![Value::number(2.0), Value::text("3")]);
        let json = serde_json::to_string(&v).unwrap();
        let back: Value = serde_json::from_str(&json).unwrap();
        assert_eq!(v, back);
    }

    #[test]
    fn legacy_binary_op_tag_migrates_to_op() {
        let json = r#"{"kind":"BinaryOp","op":"Add","lhs":{"kind":"Number","value":2.0},"rhs":{"kind":"Number","value":3.0},"saved":{"kind":"Number","value":0.0}}"#;
        let v: Value = serde_json::from_str(json).unwrap();
        assert_eq!(
            v,
            Value::op(Op::Add, vec![Value::number(2.0), Value::number(3.0)])
        );
    }

    #[test]
    fn legacy_join_tag_migrates_to_op() {
        let json = r#"{"kind":"Join","args":[{"kind":"Text","value":"a"},{"kind":"Text","value":"b"}],"saved":{"kind":"Number","value":0.0}}"#;
        let v: Value = serde_json::from_str(json).unwrap();
        assert_eq!(
            v,
            Value::op(Op::Join, vec![Value::text("a"), Value::text("b")])
        );
    }

    #[test]
    fn eval_number_nested_expression() {
        // (2 + 3) * 4 == 20
        let v = Value::op(
            Op::Mul,
            vec![
                Value::op(Op::Add, vec![Value::number(2.0), Value::number(3.0)]),
                Value::number(4.0),
            ],
        );
        assert_eq!(v.eval_number(), Ok(20.0));
    }

    #[test]
    fn eval_number_division_by_zero_errs() {
        let v = Value::op(Op::Div, vec![Value::number(1.0), Value::number(0.0)]);
        assert!(v.eval_number().is_err());
    }

    #[test]
    fn eval_number_random_integer_stays_in_range_when_both_bounds_whole() {
        let v = Value::op(Op::Random, vec![Value::number(1.0), Value::number(3.0)]);
        for _ in 0..100 {
            let n = v.eval_number().unwrap();
            assert_eq!(n.fract(), 0.0);
            assert!((1.0..=3.0).contains(&n));
        }
    }

    #[test]
    fn eval_number_random_float_when_a_bound_has_a_fraction() {
        let v = Value::op(Op::Random, vec![Value::number(1.0), Value::number(2.5)]);
        for _ in 0..100 {
            assert!((1.0..=2.5).contains(&v.eval_number().unwrap()));
        }
    }

    #[test]
    fn eval_number_random_handles_reversed_bounds() {
        let v = Value::op(Op::Random, vec![Value::number(5.0), Value::number(1.0)]);
        for _ in 0..100 {
            assert!((1.0..=5.0).contains(&v.eval_number().unwrap()));
        }
    }

    #[test]
    fn eval_number_coerces_numeric_text() {
        let v = Value::op(Op::Add, vec![Value::text("5"), Value::number(3.0)]);
        assert_eq!(v.eval_number(), Ok(8.0));
    }

    #[test]
    fn eval_number_non_numeric_text_errs() {
        assert!(Value::text("abc").eval_number().is_err());
    }

    #[test]
    fn get_mut_walks_path() {
        let mut v = Value::op(
            Op::Add,
            vec![
                Value::number(1.0),
                Value::op(Op::Mul, vec![Value::number(2.0), Value::number(3.0)]),
            ],
        );
        assert_eq!(v.get_mut(&[1, 0]), Some(&mut Value::number(2.0)));
        assert_eq!(v.get_mut(&[0]), Some(&mut Value::number(1.0)));
        assert_eq!(v.get_mut(&[5]), None);
    }

    #[test]
    fn eval_text_joins_args() {
        let v = Value::op(Op::Join, vec![Value::text("foo"), Value::text("bar")]);
        assert_eq!(v.eval_text(), Ok("foobar".to_string()));
        let v = Value::op(
            Op::Join,
            vec![Value::text("a"), Value::number(2.0), Value::text("c")],
        );
        assert_eq!(v.eval_text(), Ok("a2c".to_string()));
    }

    #[test]
    fn eval_text_new_line_and_tab_are_constants() {
        assert_eq!(Value::op(Op::NewLine, vec![]).eval_text(), Ok("\n".into()));
        assert_eq!(Value::op(Op::Tab, vec![]).eval_text(), Ok("\t".into()));
    }

    #[test]
    fn eval_number_mod_wraps_like_rem_euclid() {
        let v = Value::op(Op::Mod, vec![Value::number(-1.0), Value::number(5.0)]);
        assert_eq!(v.eval_number(), Ok(4.0));
    }

    #[test]
    fn eval_number_mod_by_zero_errs() {
        let v = Value::op(Op::Mod, vec![Value::number(1.0), Value::number(0.0)]);
        assert!(v.eval_number().is_err());
    }

    #[test]
    fn eval_number_round_rounds_half_away_from_zero() {
        let v = Value::op(Op::Round, vec![Value::number(2.5)]);
        assert_eq!(v.eval_number(), Ok(3.0));
    }

    fn math(function: &str, n: f64) -> Value {
        Value::op(Op::Math, vec![Value::text(function), Value::number(n)])
    }

    #[test]
    fn eval_number_math_functions_match_scratch_conventions() {
        assert_eq!(math("Abs", -3.5).eval_number(), Ok(3.5));
        assert_eq!(math("Floor", 2.9).eval_number(), Ok(2.0));
        assert_eq!(math("Ceiling", 2.1).eval_number(), Ok(3.0));
        assert_eq!(math("Sign", -2.0).eval_number(), Ok(-1.0));
        assert_eq!(math("Sign", 0.0).eval_number(), Ok(0.0));
        assert_eq!(math("Sign", 2.0).eval_number(), Ok(1.0));
        assert_eq!(math("Sqrt", 9.0).eval_number(), Ok(3.0));
        assert!((math("Sin", 90.0).eval_number().unwrap() - 1.0).abs() < 1e-12);
        assert!((math("Cos", 180.0).eval_number().unwrap() + 1.0).abs() < 1e-12);
        assert!((math("Tan", 45.0).eval_number().unwrap() - 1.0).abs() < 1e-12);
        assert!((math("Asin", 1.0).eval_number().unwrap() - 90.0).abs() < 1e-12);
        assert!((math("Acos", 0.0).eval_number().unwrap() - 90.0).abs() < 1e-12);
        assert!((math("Atan", 1.0).eval_number().unwrap() - 45.0).abs() < 1e-12);
        assert!((math("Ln", std::f64::consts::E).eval_number().unwrap() - 1.0).abs() < 1e-12);
        assert_eq!(math("Log", 100.0).eval_number(), Ok(2.0));
        assert_eq!(math("Log2", 8.0).eval_number(), Ok(3.0));
        assert!((math("EPower", 1.0).eval_number().unwrap() - std::f64::consts::E).abs() < 1e-12);
        assert_eq!(math("TenPower", 3.0).eval_number(), Ok(1000.0));
    }

    #[test]
    fn eval_number_math_rejects_unknown_function() {
        assert!(math("Hyperbolic", 1.0).eval_number().is_err());
    }

    #[test]
    fn eval_number_length_counts_chars_not_bytes() {
        let v = Value::op(Op::Length, vec![Value::text("héllo")]);
        assert_eq!(v.eval_number(), Ok(5.0));
    }

    #[test]
    fn eval_number_index_of_is_one_based() {
        let v = Value::op(Op::IndexOf, vec![Value::text("lo"), Value::text("hello")]);
        assert_eq!(v.eval_number(), Ok(4.0));
    }

    #[test]
    fn eval_number_index_of_not_found_is_zero() {
        let v = Value::op(Op::IndexOf, vec![Value::text("xyz"), Value::text("hello")]);
        assert_eq!(v.eval_number(), Ok(0.0));
    }

    #[test]
    fn eval_number_last_index_of_finds_final_occurrence() {
        let v = Value::op(
            Op::LastIndexOf,
            vec![Value::text("l"), Value::text("hello")],
        );
        assert_eq!(v.eval_number(), Ok(4.0));
    }

    #[test]
    fn eval_text_letter_of_is_one_based() {
        let v = Value::op(
            Op::LetterOf,
            vec![Value::number(1.0), Value::text("hello")],
        );
        assert_eq!(v.eval_text(), Ok("h".to_string()));
    }

    #[test]
    fn eval_text_letter_of_out_of_range_errs() {
        for index in [0.0, 6.0] {
            let v = Value::op(
                Op::LetterOf,
                vec![Value::number(index), Value::text("hello")],
            );
            assert!(v.eval_text().is_err());
        }
    }

    #[test]
    fn current_time_components_stay_in_range() {
        let current = |which: &str| {
            Value::op(Op::CurrentTime, vec![Value::text(which)])
                .eval_number()
                .unwrap()
        };
        assert!(current("Year") >= 2020.0);
        assert!((1.0..=12.0).contains(&current("Month")));
        assert!((1.0..=31.0).contains(&current("Date")));
        assert!((1.0..=7.0).contains(&current("DayOfWeek")));
        assert!((0.0..=23.0).contains(&current("Hour")));
        assert!((0.0..=59.0).contains(&current("Minute")));
        assert!((0.0..=59.0).contains(&current("Second")));
    }

    #[test]
    fn current_time_rejects_unknown_component() {
        let v = Value::op(Op::CurrentTime, vec![Value::text("Fortnight")]);
        assert!(v.eval_number().is_err());
    }

    #[test]
    fn eval_text_case_switches_on_its_dropdown_arg() {
        let case = |which: &str| {
            Value::op(Op::Case, vec![Value::text("Hello"), Value::text(which)]).eval_text()
        };
        assert_eq!(case("Upper"), Ok("HELLO".to_string()));
        assert_eq!(case("Lower"), Ok("hello".to_string()));
    }

    #[test]
    fn resolve_vars_replaces_leaf_with_current_value() {
        let env = HashMap::from([
            ("x".to_string(), Evaluated::Number(5.0)),
            ("s".to_string(), Evaluated::Text("hi".to_string())),
        ]);
        assert_eq!(
            Value::Var {
                name: "x".to_string()
            }
            .resolve_vars(&env),
            Value::number(5.0)
        );
        assert_eq!(
            Value::Var {
                name: "s".to_string()
            }
            .resolve_vars(&env),
            Value::text("hi")
        );
    }

    #[test]
    fn resolve_vars_defaults_missing_name_to_zero() {
        let v = Value::Var {
            name: "missing".to_string(),
        };
        assert_eq!(v.resolve_vars(&HashMap::new()), Value::number(0.0));
    }

    #[test]
    fn resolve_vars_recurses_into_op_args_and_saved() {
        let env = HashMap::from([("x".to_string(), Evaluated::Number(2.0))]);
        let v = Value::Op {
            op: Op::Add,
            args: vec![
                Value::Var {
                    name: "x".to_string(),
                },
                Value::number(3.0),
            ],
            saved: Box::new(Value::Var {
                name: "x".to_string(),
            }),
        };
        let resolved = v.resolve_vars(&env);
        assert_eq!(resolved.eval_number(), Ok(5.0));
        match resolved {
            Value::Op { saved, .. } => assert_eq!(*saved, Value::number(2.0)),
            _ => panic!("expected Op"),
        }
    }

    #[test]
    fn eval_errs_on_unresolved_var() {
        assert!(
            Value::Var {
                name: "x".to_string()
            }
            .eval()
            .is_err()
        );
    }

    #[test]
    fn rename_var_renames_matching_leaves_only() {
        let mut v = Value::Op {
            op: Op::Add,
            args: vec![
                Value::Var {
                    name: "x".to_string(),
                },
                Value::Var {
                    name: "z".to_string(),
                },
            ],
            saved: Box::new(Value::Var {
                name: "x".to_string(),
            }),
        };
        v.rename_var("x", "y");
        match v {
            Value::Op { args, saved, .. } => {
                assert_eq!(
                    args[0],
                    Value::Var {
                        name: "y".to_string()
                    }
                );
                assert_eq!(
                    args[1],
                    Value::Var {
                        name: "z".to_string()
                    }
                );
                assert_eq!(
                    *saved,
                    Value::Var {
                        name: "y".to_string()
                    }
                );
            }
            _ => panic!("expected Op"),
        }
    }

    #[test]
    fn eval_boolean_operators() {
        let t = || Value::op(Op::True, vec![]);
        let f = || Value::op(Op::False, vec![]);
        assert_eq!(t().eval(), Ok(Evaluated::Bool(true)));
        assert_eq!(f().eval(), Ok(Evaluated::Bool(false)));
        assert_eq!(
            Value::op(Op::Not, vec![t()]).eval(),
            Ok(Evaluated::Bool(false))
        );
        assert_eq!(
            Value::op(Op::And, vec![t(), f()]).eval(),
            Ok(Evaluated::Bool(false))
        );
        assert_eq!(
            Value::op(Op::Or, vec![f(), t()]).eval(),
            Ok(Evaluated::Bool(true))
        );
        // A nonzero number is truthy, so `not 5` is false.
        assert_eq!(
            Value::op(Op::Not, vec![Value::number(5.0)]).eval(),
            Ok(Evaluated::Bool(false))
        );
    }

    #[test]
    fn eval_comparisons_are_numeric() {
        let cmp = |op: Op, l: f64, r: f64| {
            Value::op(op, vec![Value::number(l), Value::number(r)]).eval()
        };
        assert_eq!(cmp(Op::Gt, 5.0, 3.0), Ok(Evaluated::Bool(true)));
        assert_eq!(cmp(Op::Lt, 5.0, 3.0), Ok(Evaluated::Bool(false)));
        assert_eq!(cmp(Op::Gte, 3.0, 3.0), Ok(Evaluated::Bool(true)));
        assert_eq!(cmp(Op::Lte, 3.0, 3.0), Ok(Evaluated::Bool(true)));
    }

    #[test]
    fn eval_eq_compares_numerically_when_both_sides_are_numeric() {
        let v = Value::op(Op::Eq, vec![Value::text("5"), Value::number(5.0)]);
        assert_eq!(v.eval(), Ok(Evaluated::Bool(true)));
        let v = Value::op(Op::Neq, vec![Value::text("5"), Value::number(5.0)]);
        assert_eq!(v.eval(), Ok(Evaluated::Bool(false)));
    }

    #[test]
    fn eval_eq_falls_back_to_text_comparison_for_non_numeric_text() {
        let eq = |l: Value, r: Value| Value::op(Op::Eq, vec![l, r]).eval();
        assert_eq!(
            eq(Value::text("hello"), Value::text("hello")),
            Ok(Evaluated::Bool(true))
        );
        assert_eq!(
            eq(Value::text("hello"), Value::text("world")),
            Ok(Evaluated::Bool(false))
        );
        assert_eq!(
            eq(Value::text("hello"), Value::number(5.0)),
            Ok(Evaluated::Bool(false))
        );
    }

    #[test]
    fn as_bool_coerces_loosely() {
        assert!(Evaluated::Number(1.0).as_bool());
        assert!(!Evaluated::Number(0.0).as_bool());
        assert!(Evaluated::Text("hi".to_string()).as_bool());
        assert!(!Evaluated::Text(String::new()).as_bool());
        assert!(!Evaluated::Text("false".to_string()).as_bool());
    }

    #[test]
    fn into_value_rebuilds_bool_as_true_false_op() {
        assert_eq!(
            Evaluated::Bool(true).into_value().eval(),
            Ok(Evaluated::Bool(true))
        );
        assert_eq!(
            Evaluated::Bool(false).into_value().eval(),
            Ok(Evaluated::Bool(false))
        );
    }

    static TEST_OPERATORS: &[ExtOperator] = &[ExtOperator {
        kind: "AnswerToEverything",
        op: "AnswerToEverything",
        arity: 0,
        default_args: Vec::new,
        eval: |_| Ok(Evaluated::Number(42.0)),
    }];

    #[test]
    fn registered_ext_operator_evaluates_and_joins_the_palette() {
        register_operators(TEST_OPERATORS);
        let v = Value::op(Op::from_name("AnswerToEverything"), vec![]);
        assert_eq!(v.eval_number(), Ok(42.0));
        assert_eq!(operator_kind("AnswerToEverything").unwrap().arity, 0);
    }

    #[test]
    fn unregistered_ext_operator_round_trips_but_errs_on_eval() {
        let json = r#"{"kind":"Op","op":"NeverRegistered","args":[],"saved":{"kind":"Number","value":0.0}}"#;
        let v: Value = serde_json::from_str(json).unwrap();
        assert_eq!(serde_json::to_string(&v).unwrap(), json);
        assert!(v.eval().is_err());
    }
}
