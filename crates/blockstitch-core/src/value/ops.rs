//! The operator vocabulary of a [`Value`] tree: the built-in [`Op`] set,
//! the palette entries that build them, and the host registry.

use super::{Evaluated, Value};
use serde::{Deserialize, Deserializer, Serialize, Serializer};
use std::sync::RwLock;

/// Operator for a [`Value::Op`] block - arithmetic, text, logic, a
/// zero-arity constant, or [`Op::Ext`] for a host-registered one.
#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub enum Op {
    Add,
    Sub,
    Mul,
    Div,
    /// `args[0] % args[1]` via `rem_euclid` (not Rust's `%`), so a negative
    /// left-hand side still wraps normally. Errs on a zero right-hand side.
    Mod,
    /// `args[0]` rounded to the nearest whole number (half away from zero).
    Round,
    /// Applies the numeric function named by `args[0]` (a fixed dropdown)
    /// to `args[1]`. Trigonometric inputs and outputs are in degrees.
    Math,
    /// `args[0]`/`args[1]` are inclusive bounds, resampled on every `eval`.
    /// Integer if both bounds are whole, otherwise a float.
    Random,
    /// Concatenates all of `args` as text - the only variable-arity built-in
    /// (2 or 3 args depending on which palette entry it came from).
    Join,
    /// Zero-arity text constants - `args` is always empty.
    NewLine,
    Tab,
    /// 1-based index of `args[0]` (needle) in `args[1]` (haystack), or `0` if
    /// not found. Character-based, matching `LetterOf`'s indexing.
    IndexOf,
    /// Same as `IndexOf`, but the index of the last occurrence.
    LastIndexOf,
    /// The single character at `args[0]` (1-based) of `args[1]` (as text).
    /// Errs if the index is out of range.
    LetterOf,
    /// Character count of `args[0]` (as text).
    Length,
    /// Upper/lowercases `args[0]` per `args[1]` (`"Upper"`/`"Lower"`), which
    /// an in-place dropdown writes rather than the drag/drop machinery.
    Case,
    /// `args[0] == args[1]` - numeric if both sides parse as a number,
    /// otherwise a text comparison (mirrors Scratch's loose `=`).
    Eq,
    /// Negation of [`Op::Eq`].
    Neq,
    /// `args[0] > args[1]`, numeric (same coercion as the arithmetic ops).
    Gt,
    /// `args[0] < args[1]`.
    Lt,
    /// `args[0] >= args[1]`.
    Gte,
    /// `args[0] <= args[1]`.
    Lte,
    /// `args[0] && args[1]`, short-circuiting.
    And,
    /// `args[0] || args[1]`, short-circuiting.
    Or,
    /// `!args[0]`.
    Not,
    /// Zero-arity `true` literal - a standalone block, not a toggle.
    True,
    /// Zero-arity `false` literal - a standalone block, not a toggle.
    False,
    /// Reads the local-clock component named by `args[0]` (`"Year"` ...
    /// `"Second"`). `DayOfWeek` is 1 (Sunday) to 7, and `Hour` is always
    /// 24-hour whatever the UI displays, matching Scratch's "current ()".
    CurrentTime,
    /// A host-registered operator (see [`register_operators`]). Holds the
    /// wire name, so an unregistered op still round-trips through a save
    /// file and only errors on `eval`. Boxed to keep [`Op`] small.
    Ext(Box<str>),
}

impl Op {
    /// Wire name - what this op serializes as, and the key an [`ExtOperator`]
    /// is registered under.
    pub fn name(&self) -> &str {
        match self {
            Op::Add => "Add",
            Op::Sub => "Sub",
            Op::Mul => "Mul",
            Op::Div => "Div",
            Op::Mod => "Mod",
            Op::Round => "Round",
            Op::Math => "Math",
            Op::Random => "Random",
            Op::Join => "Join",
            Op::NewLine => "NewLine",
            Op::Tab => "Tab",
            Op::IndexOf => "IndexOf",
            Op::LastIndexOf => "LastIndexOf",
            Op::LetterOf => "LetterOf",
            Op::Length => "Length",
            Op::Case => "Case",
            Op::Eq => "Eq",
            Op::Neq => "Neq",
            Op::Gt => "Gt",
            Op::Lt => "Lt",
            Op::Gte => "Gte",
            Op::Lte => "Lte",
            Op::And => "And",
            Op::Or => "Or",
            Op::Not => "Not",
            Op::True => "True",
            Op::False => "False",
            Op::CurrentTime => "CurrentTime",
            Op::Ext(name) => name,
        }
    }

    /// Inverse of [`Op::name`] - any name that isn't built in becomes
    /// [`Op::Ext`], whether or not a host registered it.
    pub fn from_name(name: &str) -> Op {
        match name {
            "Add" => Op::Add,
            "Sub" => Op::Sub,
            "Mul" => Op::Mul,
            "Div" => Op::Div,
            "Mod" => Op::Mod,
            "Round" => Op::Round,
            "Math" => Op::Math,
            "Random" => Op::Random,
            "Join" => Op::Join,
            "NewLine" => Op::NewLine,
            "Tab" => Op::Tab,
            "IndexOf" => Op::IndexOf,
            "LastIndexOf" => Op::LastIndexOf,
            "LetterOf" => Op::LetterOf,
            "Length" => Op::Length,
            "Case" => Op::Case,
            "Eq" => Op::Eq,
            "Neq" => Op::Neq,
            "Gt" => Op::Gt,
            "Lt" => Op::Lt,
            "Gte" => Op::Gte,
            "Lte" => Op::Lte,
            "And" => Op::And,
            "Or" => Op::Or,
            "Not" => Op::Not,
            "True" => Op::True,
            "False" => Op::False,
            "CurrentTime" => Op::CurrentTime,
            other => Op::Ext(other.into()),
        }
    }
}

/// Serialized as the bare variant name, exactly as a derive would for a
/// unit variant - so a host operator stays loadable by a build without it.
impl Serialize for Op {
    fn serialize<S: Serializer>(&self, serializer: S) -> Result<S::Ok, S::Error> {
        serializer.serialize_str(self.name())
    }
}

impl<'de> Deserialize<'de> for Op {
    fn deserialize<D: Deserializer<'de>>(deserializer: D) -> Result<Self, D::Error> {
        Ok(Op::from_name(&String::deserialize(deserializer)?))
    }
}

/// Per-palette-entry metadata for building a freshly dropped block. Arity
/// lives here, not on [`Op`]: `Op::Join` covers both the 2- and 3-arg entry.
pub struct OperatorKindSpec {
    /// Palette entry id, as the frontend names it.
    pub kind: &'static str,
    /// Wire name of the operator this entry builds - see [`Op::name`].
    pub op: &'static str,
    pub arity: usize,
    /// Builds the default `args` - a function, not a fixed `Vec`, so a
    /// mixed-type operator like `LetterOf` can give each slot its own.
    pub default_args: fn() -> Vec<Value>,
}

/// An operator contributed by the host. `args` reach `eval` already
/// evaluated, so an extension can't short-circuit the way `And`/`Or` do.
pub struct ExtOperator {
    /// Palette entry id, as the frontend names it - usually the same as `op`.
    pub kind: &'static str,
    /// Wire name, stored in save files. Must be stable, and must not collide
    /// with a built-in (a built-in always wins the lookup).
    pub op: &'static str,
    pub arity: usize,
    pub default_args: fn() -> Vec<Value>,
    pub eval: fn(&[Evaluated]) -> Result<Evaluated, String>,
}

fn text_default() -> Value {
    Value::Text {
        value: String::new(),
    }
}

/// Default for a boolean-typed operand slot - blank (`Value::Bool`), same
/// spirit as `text_default`, not a pre-filled `false`.
fn bool_default() -> Value {
    Value::Bool
}

fn zeroes(n: usize) -> Vec<Value> {
    (0..n).map(|_| Value::number(0.0)).collect()
}

fn two_zeroes() -> Vec<Value> {
    zeroes(2)
}

fn one_zero() -> Vec<Value> {
    zeroes(1)
}

fn two_texts() -> Vec<Value> {
    vec![text_default(), text_default()]
}

pub const BUILTIN_OPERATOR_KINDS: &[OperatorKindSpec] = &[
    OperatorKindSpec {
        kind: "Add",
        op: "Add",
        arity: 2,
        default_args: two_zeroes,
    },
    OperatorKindSpec {
        kind: "Sub",
        op: "Sub",
        arity: 2,
        default_args: two_zeroes,
    },
    OperatorKindSpec {
        kind: "Mul",
        op: "Mul",
        arity: 2,
        default_args: two_zeroes,
    },
    OperatorKindSpec {
        kind: "Div",
        op: "Div",
        arity: 2,
        default_args: two_zeroes,
    },
    OperatorKindSpec {
        kind: "Mod",
        op: "Mod",
        arity: 2,
        default_args: two_zeroes,
    },
    OperatorKindSpec {
        kind: "Round",
        op: "Round",
        arity: 1,
        default_args: one_zero,
    },
    OperatorKindSpec {
        kind: "Math",
        op: "Math",
        arity: 2,
        default_args: || {
            vec![
                Value::Text {
                    value: "Abs".to_string(),
                },
                Value::number(0.0),
            ]
        },
    },
    OperatorKindSpec {
        kind: "Random",
        op: "Random",
        arity: 2,
        default_args: two_zeroes,
    },
    OperatorKindSpec {
        kind: "Join",
        op: "Join",
        arity: 2,
        default_args: two_texts,
    },
    OperatorKindSpec {
        kind: "Join3",
        op: "Join",
        arity: 3,
        default_args: || vec![text_default(), text_default(), text_default()],
    },
    // `default_args` is unused for these - arity 0 means it's never called.
    OperatorKindSpec {
        kind: "NewLine",
        op: "NewLine",
        arity: 0,
        default_args: Vec::new,
    },
    OperatorKindSpec {
        kind: "Tab",
        op: "Tab",
        arity: 0,
        default_args: Vec::new,
    },
    OperatorKindSpec {
        kind: "IndexOf",
        op: "IndexOf",
        arity: 2,
        default_args: two_texts,
    },
    OperatorKindSpec {
        kind: "LastIndexOf",
        op: "LastIndexOf",
        arity: 2,
        default_args: two_texts,
    },
    OperatorKindSpec {
        kind: "LetterOf",
        op: "LetterOf",
        arity: 2,
        default_args: || vec![Value::number(1.0), text_default()],
    },
    OperatorKindSpec {
        kind: "Length",
        op: "Length",
        arity: 1,
        default_args: || vec![text_default()],
    },
    // `args[1]` defaults to the dropdown's "uppercase" option - see
    // `Op::Case`'s doc comment.
    OperatorKindSpec {
        kind: "Case",
        op: "Case",
        arity: 2,
        default_args: || {
            vec![
                text_default(),
                Value::Text {
                    value: "Upper".to_string(),
                },
            ]
        },
    },
    OperatorKindSpec {
        kind: "Eq",
        op: "Eq",
        arity: 2,
        default_args: two_zeroes,
    },
    OperatorKindSpec {
        kind: "Neq",
        op: "Neq",
        arity: 2,
        default_args: two_zeroes,
    },
    OperatorKindSpec {
        kind: "Gt",
        op: "Gt",
        arity: 2,
        default_args: two_zeroes,
    },
    OperatorKindSpec {
        kind: "Lt",
        op: "Lt",
        arity: 2,
        default_args: two_zeroes,
    },
    OperatorKindSpec {
        kind: "Gte",
        op: "Gte",
        arity: 2,
        default_args: two_zeroes,
    },
    OperatorKindSpec {
        kind: "Lte",
        op: "Lte",
        arity: 2,
        default_args: two_zeroes,
    },
    OperatorKindSpec {
        kind: "And",
        op: "And",
        arity: 2,
        default_args: || vec![bool_default(), bool_default()],
    },
    OperatorKindSpec {
        kind: "Or",
        op: "Or",
        arity: 2,
        default_args: || vec![bool_default(), bool_default()],
    },
    OperatorKindSpec {
        kind: "Not",
        op: "Not",
        arity: 1,
        default_args: || vec![bool_default()],
    },
    // Zero-arity, like NewLine/Tab - a standalone "true"/"false" block, not a toggle.
    OperatorKindSpec {
        kind: "True",
        op: "True",
        arity: 0,
        default_args: Vec::new,
    },
    OperatorKindSpec {
        kind: "False",
        op: "False",
        arity: 0,
        default_args: Vec::new,
    },
    // `args[0]` defaults to the dropdown's first ("Year") option, matching
    // what the frontend gives a freshly dragged block.
    OperatorKindSpec {
        kind: "CurrentTime",
        op: "CurrentTime",
        arity: 1,
        default_args: || {
            vec![Value::Text {
                value: "Year".to_string(),
            }]
        },
    },
];

static EXT_OPERATORS: RwLock<Vec<&'static ExtOperator>> = RwLock::new(Vec::new());

/// Adds host operators to the palette and to [`Value::eval`]'s dispatch.
/// Call it during startup, before any saved tree is evaluated. Registering
/// the same wire name twice keeps the first, so extra calls are harmless.
pub fn register_operators(operators: &'static [ExtOperator]) {
    let mut registry = match EXT_OPERATORS.write() {
        Ok(registry) => registry,
        Err(poisoned) => poisoned.into_inner(),
    };
    for operator in operators {
        if !registry.iter().any(|existing| existing.op == operator.op) {
            registry.push(operator);
        }
    }
}

/// The host operator registered under `op`'s wire name, if any.
pub fn ext_operator(op: &str) -> Option<&'static ExtOperator> {
    let registry = match EXT_OPERATORS.read() {
        Ok(registry) => registry,
        Err(poisoned) => poisoned.into_inner(),
    };
    registry
        .iter()
        .find(|candidate| candidate.op == op)
        .copied()
}

/// One palette entry, built-in or host-registered - what a sidebar drop
/// needs to construct a fresh operator node.
pub struct OperatorKind {
    pub kind: String,
    pub op: Op,
    pub arity: usize,
    pub default_args: fn() -> Vec<Value>,
}

/// Looks up a palette entry by its kind string. Built-ins shadow host
/// operators, so an app can't accidentally redefine `Add`.
pub fn operator_kind(kind: &str) -> Option<OperatorKind> {
    if let Some(spec) = BUILTIN_OPERATOR_KINDS.iter().find(|spec| spec.kind == kind) {
        return Some(OperatorKind {
            kind: spec.kind.to_string(),
            op: Op::from_name(spec.op),
            arity: spec.arity,
            default_args: spec.default_args,
        });
    }
    let registry = match EXT_OPERATORS.read() {
        Ok(registry) => registry,
        Err(poisoned) => poisoned.into_inner(),
    };
    registry
        .iter()
        .find(|operator| operator.kind == kind)
        .map(|operator| OperatorKind {
            kind: operator.kind.to_string(),
            op: Op::from_name(operator.op),
            arity: operator.arity,
            default_args: operator.default_args,
        })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn unknown_op_name_becomes_ext_and_round_trips() {
        let op: Op = serde_json::from_str("\"BatteryPercentage\"").unwrap();
        assert_eq!(op, Op::Ext("BatteryPercentage".into()));
        assert_eq!(serde_json::to_string(&op).unwrap(), "\"BatteryPercentage\"");
    }

    #[test]
    fn builtin_op_wire_name_is_the_variant_name() {
        assert_eq!(serde_json::to_string(&Op::Add).unwrap(), "\"Add\"");
        assert_eq!(Op::from_name("Add"), Op::Add);
    }

    #[test]
    fn operator_kind_covers_both_join_arities() {
        assert_eq!(operator_kind("Join").unwrap().arity, 2);
        assert_eq!(operator_kind("Join3").unwrap().arity, 3);
        assert_eq!(operator_kind("Join3").unwrap().op, Op::Join);
    }
}
