//! Serializable descriptions of every palette operator: what a fresh one
//! holds, what each slot takes and what it reports. Built from the same
//! tables [`operator_kind`](super::operator_kind) and the evaluator use, so
//! a frontend never has to restate a default.

use super::ops::{BUILTIN_OPERATOR_KINDS, registered_operators};
use super::{Op, Value};
use serde::{Deserialize, Serialize};

/// What a slot holds or an operator reports.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum ValueType {
    Number,
    Text,
    Bool,
}

/// The document names a slot picks from.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum NameSource {
    List,
    Dict,
}

/// One operand slot.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ArgDescriptor {
    #[serde(rename = "type")]
    pub ty: ValueType,
    /// What a fresh operator holds here.
    pub default: Value,
    /// The only words the evaluator accepts, for a fixed dropdown slot.
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub choices: Vec<String>,
    /// Set when the slot holds a list or dict name rather than a value.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub names: Option<NameSource>,
    /// A position counted from 1.
    #[serde(default, skip_serializing_if = "std::ops::Not::not")]
    pub one_based: bool,
}

/// One palette entry, built-in or host-registered.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct OperatorDescriptor {
    /// Palette entry id. Usually the wire name; `Join3` builds `Join`.
    pub kind: String,
    /// Wire name, as saved - see [`Op::name`].
    pub op: String,
    pub arity: usize,
    /// `None` for a host operator: the host's presentation says.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub result: Option<ValueType>,
    pub args: Vec<ArgDescriptor>,
    /// Registered by the host rather than built into blockstitch.
    #[serde(default, skip_serializing_if = "std::ops::Not::not")]
    pub host: bool,
}

impl OperatorDescriptor {
    /// The operator a palette drop makes: these defaults, with a zero as the
    /// displaced value.
    pub fn fresh_value(&self) -> Value {
        Value::op(
            Op::from_name(&self.op),
            self.args.iter().map(|arg| arg.default.clone()).collect(),
        )
    }
}

const MATH_FUNCTIONS: &[&str] = &[
    "Abs", "Floor", "Ceiling", "Sign", "Sqrt", "Sin", "Cos", "Tan", "Asin", "Acos", "Atan", "Ln",
    "Log", "Log2", "EPower", "TenPower",
];
const CASES: &[&str] = &["Upper", "Lower"];
const TIME_PARTS: &[&str] = &[
    "Year",
    "Month",
    "Date",
    "DayOfWeek",
    "Hour",
    "Minute",
    "Second",
];

/// A built-in's result, its fixed dropdowns by slot, and its 1-based slots.
type Traits = (
    ValueType,
    &'static [(usize, &'static [&'static str])],
    &'static [usize],
);

/// Result type and per-slot constraints of a built-in, by wire name.
fn builtin_traits(op: &str) -> Traits {
    use ValueType::*;
    match op {
        "Add" | "Sub" | "Mul" | "Div" | "Mod" | "Round" | "Random" | "IndexOf" | "LastIndexOf"
        | "Length" => (Number, &[], &[]),
        "Math" => (Number, &[(0, MATH_FUNCTIONS)], &[]),
        "CurrentTime" => (Number, &[(0, TIME_PARTS)], &[]),
        "Case" => (Text, &[(1, CASES)], &[]),
        "LetterOf" => (Text, &[], &[0]),
        "Join" | "NewLine" | "Tab" => (Text, &[], &[]),
        _ => (Bool, &[], &[]),
    }
}

fn type_of(value: &Value) -> ValueType {
    match value {
        Value::Number { .. } => ValueType::Number,
        Value::Bool => ValueType::Bool,
        Value::Op { op, .. } => op_result(op.name()).unwrap_or(ValueType::Text),
        _ => ValueType::Text,
    }
}

fn op_result(op: &str) -> Option<ValueType> {
    if BUILTIN_OPERATOR_KINDS.iter().any(|spec| spec.op == op) {
        return Some(builtin_traits(op).0);
    }
    COLLECTION_REPORTERS
        .iter()
        .find(|reporter| reporter.0 == op)
        .map(|reporter| reporter.1)
}

/// The list and dict reporters the core resolves (see `graph::lists` and
/// `graph::dicts`): wire name, result, then each slot. A `None` slot is the
/// collection's name; `Some` is a placeholder value, with `true` for a
/// 1-based position.
type CollectionSlot = Option<(fn() -> Value, bool)>;
const COLLECTION_REPORTERS: &[(&str, ValueType, NameSource, &[CollectionSlot])] = {
    use NameSource::*;
    use ValueType::*;
    const NAME: CollectionSlot = None;
    const INDEX: CollectionSlot = Some((one, true));
    const THING: CollectionSlot = Some((thing, false));
    const KEY: CollectionSlot = Some((key, false));
    &[
        ("ListItem", Text, List, &[INDEX, NAME]),
        ("ListItemNumber", Number, List, &[THING, NAME]),
        ("ListAmount", Number, List, &[THING, NAME]),
        ("ListLength", Number, List, &[NAME]),
        ("ListContains", Bool, List, &[NAME, THING]),
        ("ListItemExists", Bool, List, &[INDEX, NAME]),
        ("ListIsEmpty", Bool, List, &[NAME]),
        ("ListAsJson", Text, List, &[NAME]),
        ("DictValue", Text, Dict, &[KEY, NAME]),
        ("DictHasKey", Bool, Dict, &[NAME, KEY]),
        ("DictSize", Number, Dict, &[NAME]),
        ("DictKeys", Text, Dict, &[NAME]),
        ("DictAsJson", Text, Dict, &[NAME]),
        ("DictIsEmpty", Bool, Dict, &[NAME]),
    ]
};

fn one() -> Value {
    Value::number(1.0)
}
fn thing() -> Value {
    Value::text("thing")
}
fn key() -> Value {
    Value::text("key")
}

fn plain_arg(default: Value) -> ArgDescriptor {
    ArgDescriptor {
        ty: type_of(&default),
        default,
        choices: Vec::new(),
        names: None,
        one_based: false,
    }
}

/// Descriptors of blockstitch's own operators, list and dict reporters
/// included, in palette order. The same for every host.
pub fn builtin_operator_descriptors() -> Vec<OperatorDescriptor> {
    let operators = BUILTIN_OPERATOR_KINDS.iter().map(|spec| {
        let (result, choices, one_based) = builtin_traits(spec.op);
        let args = (spec.default_args)()
            .into_iter()
            .take(spec.arity)
            .enumerate()
            .map(|(i, default)| {
                let mut arg = plain_arg(default);
                if let Some((_, words)) = choices.iter().find(|(at, _)| *at == i) {
                    arg.choices = words.iter().map(|w| w.to_string()).collect();
                }
                arg.one_based = one_based.contains(&i);
                arg
            })
            .collect();
        OperatorDescriptor {
            kind: spec.kind.to_string(),
            op: spec.op.to_string(),
            arity: spec.arity,
            result: Some(result),
            args,
            host: false,
        }
    });
    let collections = COLLECTION_REPORTERS
        .iter()
        .map(|(op, result, source, slots)| {
            let args = slots
                .iter()
                .map(|slot| match slot {
                    None => ArgDescriptor {
                        names: Some(*source),
                        ..plain_arg(Value::text(""))
                    },
                    Some((default, one_based)) => ArgDescriptor {
                        one_based: *one_based,
                        ..plain_arg(default())
                    },
                })
                .collect();
            OperatorDescriptor {
                kind: op.to_string(),
                op: op.to_string(),
                arity: slots.len(),
                result: Some(*result),
                args,
                host: false,
            }
        });
    operators.chain(collections).collect()
}

/// Descriptors of the host's registered operators, in registration order.
/// A host operator a built-in shadows is left out, as the lookup does.
pub fn host_operator_descriptors() -> Vec<OperatorDescriptor> {
    let builtin = builtin_operator_descriptors();
    registered_operators()
        .into_iter()
        .filter(|ext| !builtin.iter().any(|d| d.kind == ext.kind || d.op == ext.op))
        .map(|ext| {
            let mut defaults = (ext.default_args)();
            defaults.truncate(ext.arity);
            OperatorDescriptor {
                kind: ext.kind.to_string(),
                op: ext.op.to_string(),
                arity: ext.arity,
                result: None,
                args: defaults.into_iter().map(plain_arg).collect(),
                host: true,
            }
        })
        .collect()
}

/// Every palette operator: the built-ins, then the host's.
pub fn operator_descriptors() -> Vec<OperatorDescriptor> {
    let mut all = builtin_operator_descriptors();
    all.extend(host_operator_descriptors());
    all
}

/// The descriptor for one palette entry. Unlike
/// [`operator_kind`](super::operator_kind) this also knows the list and
/// dict reporters.
pub fn operator_descriptor(kind: &str) -> Option<OperatorDescriptor> {
    operator_descriptors().into_iter().find(|d| d.kind == kind)
}

/// `descriptors` as the QML block a frontend embeds: one JSON object per
/// line, two-space-indented under an array, so a regenerated file diffs by
/// operator.
pub fn render_descriptors_qml(descriptors: &[OperatorDescriptor], indent: &str) -> String {
    let mut out = String::from("[\n");
    for (i, descriptor) in descriptors.iter().enumerate() {
        let json = serde_json::to_string(descriptor).expect("descriptors serialize");
        let comma = if i + 1 < descriptors.len() { "," } else { "" };
        out.push_str(&format!("{indent}    {json}{comma}\n"));
    }
    out.push_str(indent);
    out.push(']');
    out
}

/// Replaces what sits between `begin` and `end` marker lines in `text` with
/// `block`, for a drift test that also rewrites. `None` when a marker is
/// missing.
pub fn replace_generated(text: &str, begin: &str, end: &str, block: &str) -> Option<String> {
    let start = text.find(begin)? + begin.len();
    let start = start + text[start..].find('\n')? + 1;
    let stop = start + text[start..].find(end)?;
    let stop = text[..stop].rfind('\n').map_or(stop, |n| n + 1);
    Some(format!("{}{block}\n{}", &text[..start], &text[stop..]))
}
