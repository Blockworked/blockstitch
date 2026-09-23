//! Named, document-scoped dicts: string-keyed collections of literal
//! number/text values, parallel to [`crate::graph::lists`] but keyed
//! instead of ordered. A host document owns them through
//! [`crate::graph::BlockGraph::dicts`]; the reporter operators below
//! (`DictValue`, `DictSize`, ...) read them from a live [`DictStore`].
//!
//! The JSON helpers here bridge dicts and lists to plain text: a dict
//! serializes as a JSON object, a list as a JSON array, both holding only
//! numbers and strings. Anything else in the parsed JSON is an error, the
//! same way a boolean is never a list item.

use crate::value::{Evaluated, Op, Value};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::sync::{Arc, Mutex};

/// Shared, document-wide dict contents, parallel to a variable store: dict
/// name to its current entries. One `Arc` is shared across a run's threads
/// so a mutation in one strand is visible to the others.
pub type DictStore = Arc<Mutex<HashMap<String, Vec<DictEntry>>>>;

/// One dict entry: a string key with a literal-only value. Like a list
/// item, the value cannot be an expression, variable, or custom-block call.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct DictEntry {
    pub key: String,
    pub value: DictItem,
}

impl DictEntry {
    pub fn new(key: String, value: DictItem) -> Self {
        Self { key, value }
    }
}

impl std::hash::Hash for DictEntry {
    fn hash<H: std::hash::Hasher>(&self, state: &mut H) {
        self.key.hash(state);
        self.value.hash(state);
    }
}

/// A dict value is deliberately a literal only: unlike an instruction field
/// it cannot contain an expression, variable, or custom-block call. This
/// keeps a saved dict stable and makes the editor safe to edit directly.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(tag = "kind", content = "value")]
pub enum DictItem {
    Number(f64),
    Text(String),
}

impl DictItem {
    pub fn from_evaluated(value: Evaluated) -> Option<Self> {
        match value {
            Evaluated::Number(value) => Some(Self::Number(value)),
            Evaluated::Text(value) => Some(Self::Text(value)),
            Evaluated::Bool(_) => None,
        }
    }

    pub fn evaluated(&self) -> Evaluated {
        match self {
            Self::Number(value) => Evaluated::Number(*value),
            Self::Text(value) => Evaluated::Text(value.clone()),
        }
    }
}

impl std::hash::Hash for DictItem {
    fn hash<H: std::hash::Hasher>(&self, state: &mut H) {
        match self {
            Self::Number(value) => {
                0u8.hash(state);
                value.to_bits().hash(state);
            }
            Self::Text(value) => {
                1u8.hash(state);
                value.hash(state);
            }
        }
    }
}

/// A named, document-scoped collection. Dicts live alongside variables and
/// lists but hold keyed literal number/text values (see [`DictItem`]).
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct DictDef {
    pub name: String,
    #[serde(default)]
    pub entries: Vec<DictEntry>,
    /// Whether the editable dict monitor is visible on the canvas. This is
    /// persisted with its document so reopening the app restores it.
    #[serde(default)]
    pub editor_visible: bool,
    /// Canvas position of the editable dict monitor in CSS pixels.
    #[serde(default)]
    pub editor_x: i32,
    /// Canvas position of the editable dict monitor in CSS pixels.
    #[serde(default)]
    pub editor_y: i32,
}

impl std::hash::Hash for DictDef {
    fn hash<H: std::hash::Hasher>(&self, state: &mut H) {
        self.name.hash(state);
        self.entries.hash(state);
        self.editor_visible.hash(state);
        self.editor_x.hash(state);
        self.editor_y.hash(state);
    }
}

/// Looks up `key` in `entries`, last write wins when keys repeat.
pub fn dict_lookup<'a>(entries: &'a [DictEntry], key: &str) -> Option<&'a DictItem> {
    entries.iter().rev().find(|entry| entry.key == key).map(|entry| &entry.value)
}

/// Sets `key` to `value`, replacing the last entry with that key or pushing
/// a new one. Keys that differ only by position collapse on write, so a
/// dict never holds the same key twice after a mutation.
pub fn dict_set(entries: &mut Vec<DictEntry>, key: String, value: DictItem) {
    if let Some(entry) = entries.iter_mut().rev().find(|entry| entry.key == key) {
        entry.value = value;
    } else {
        entries.push(DictEntry { key, value });
    }
}

/// Removes every entry with `key`, returning whether one was there.
pub fn dict_remove(entries: &mut Vec<DictEntry>, key: &str) -> bool {
    let before = entries.len();
    entries.retain(|entry| entry.key != key);
    entries.len() != before
}

/// Arg index holding the dict name for a dict-reporter op, by wire name.
/// The name is the second arg for `DictValue` and the first for the rest.
pub fn dict_reporter_name_index(op_name: &str) -> Option<usize> {
    match op_name {
        "DictValue" => Some(1),
        "DictHasKey" | "DictSize" | "DictIsEmpty" | "DictKeys" | "DictAsJson" => Some(0),
        _ => None,
    }
}

/// True for a value-position dict reporter (`Op::Ext` with a dict wire
/// name) - resolved against the live dicts, never by plain `Value::eval`.
pub fn is_dict_reporter(op: &Op) -> bool {
    match op {
        Op::Ext(name) => dict_reporter_name_index(name).is_some(),
        _ => false,
    }
}

/// Renames a dict reference inside a value tree: a dict reporter's name arg
/// (a plain `Text` leaf) plus every nested arg. Call args recurse too, since
/// a reporter can sit inside a custom-block call.
pub fn rename_dict_in_value(value: &mut Value, old: &str, new: &str) {
    match value {
        Value::Op { op, args, saved } => {
            if let Op::Ext(name) = op
                && let Some(index) = dict_reporter_name_index(name)
                && let Some(Value::Text { value: name_arg }) = args.get_mut(index)
                && name_arg == old
            {
                *name_arg = new.to_string();
            }
            for arg in args.iter_mut() {
                rename_dict_in_value(arg, old, new);
            }
            rename_dict_in_value(saved, old, new);
        }
        Value::Call {
            block_id: _,
            args,
            branches: _,
            saved,
        } => {
            for arg in args.iter_mut() {
                rename_dict_in_value(arg, old, new);
            }
            rename_dict_in_value(saved, old, new);
        }
        Value::Number { .. } | Value::Text { .. } | Value::Bool | Value::Var { .. } | Value::Param { .. } => {}
    }
}

/// Serializes dict entries as a JSON object, in entry order. Numbers stay
/// numeric, text is quoted - the inverse of [`parse_json_object`].
pub fn dict_to_json(entries: &[DictEntry]) -> String {
    let mut out = String::from("{");
    for (index, entry) in entries.iter().enumerate() {
        if index > 0 {
            out.push(',');
        }
        out.push_str(&serde_json::to_string(&entry.key).unwrap_or_else(|_| "\"\"".to_string()));
        out.push(':');
        match &entry.value {
            DictItem::Number(value) => out.push_str(&json_number(*value)),
            DictItem::Text(value) => {
                out.push_str(&serde_json::to_string(value).unwrap_or_else(|_| "\"\"".to_string()))
            }
        }
    }
    out.push('}');
    out
}

fn json_number(value: f64) -> String {
    if !value.is_finite() {
        return "null".to_string();
    }
    serde_json::to_string(&value).unwrap_or_else(|_| "null".to_string())
}

fn json_item_value(json: &serde_json::Value) -> Option<DictItem> {
    match json {
        serde_json::Value::Number(value) => value.as_f64().map(DictItem::Number),
        serde_json::Value::String(value) => Some(DictItem::Text(value.clone())),
        _ => None,
    }
}

/// Parses a JSON object into dict entries, in document order. Only numbers
/// and strings are valid values - anything else (booleans, null, nested
/// objects or arrays) is an error naming the offending key.
pub fn parse_json_object(text: &str) -> Result<Vec<DictEntry>, String> {
    let json: serde_json::Value =
        serde_json::from_str(text).map_err(|_| "that text isn't a JSON object".to_string())?;
    let serde_json::Value::Object(map) = json else {
        return Err("that text isn't a JSON object".to_string());
    };
    map.into_iter()
        .map(|(key, json)| {
            json_item_value(&json)
                .map(|value| DictEntry { key: key.clone(), value })
                .ok_or_else(|| format!("\"{key}\" isn't a number or text"))
        })
        .collect()
}

/// Resolves one dict reporter whose arguments have already been reduced to
/// ordinary values. Shared by a host's runner and the editor's
/// click-to-preview evaluator so the two always agree about dict semantics.
pub fn resolve_dict_reporter(
    op_name: &str,
    args: Vec<Value>,
    dicts: &HashMap<String, Vec<DictEntry>>,
) -> Result<Value, String> {
    let text = |index: usize| {
        args.get(index)
            .ok_or_else(|| "missing dict reporter argument".to_string())
            .and_then(Value::eval_text)
    };
    let dict_name = match op_name {
        "DictValue" => text(1)?,
        "DictHasKey" | "DictSize" | "DictIsEmpty" | "DictKeys" | "DictAsJson" => text(0)?,
        _ => return Err("not a dict reporter".to_string()),
    };
    let entries = dicts.get(&dict_name).cloned().unwrap_or_default();
    let evaluated = match op_name {
        "DictValue" => {
            let key = text(0)?;
            dict_lookup(&entries, &key)
                .map(DictItem::evaluated)
                .unwrap_or(Evaluated::Text(String::new()))
        }
        "DictHasKey" => {
            let key = text(1)?;
            Evaluated::Bool(entries.iter().any(|entry| entry.key == key))
        }
        "DictSize" => {
            let mut seen = std::collections::HashSet::new();
            for entry in &entries {
                seen.insert(entry.key.as_str());
            }
            Evaluated::Number(seen.len() as f64)
        }
        "DictIsEmpty" => Evaluated::Bool(entries.is_empty()),
        "DictKeys" => {
            let mut keys = Vec::new();
            for entry in &entries {
                if !keys.contains(&entry.key) {
                    keys.push(entry.key.clone());
                }
            }
            let json: Vec<String> =
                keys.iter().map(|key| serde_json::to_string(key).unwrap_or_default()).collect();
            Evaluated::Text(format!("[{}]", json.join(",")))
        }
        "DictAsJson" => Evaluated::Text(dict_to_json(&entries)),
        _ => unreachable!("validated by is_dict_reporter"),
    };
    Ok(evaluated.into_value())
}

/// Replaces dict reporter nodes with their values from `dicts`, without
/// executing custom-block calls. Useful for non-running contexts such as a
/// canvas reporter preview; a host's full runner adds call/parameter
/// resolution on top.
pub fn resolve_dict_reporters(
    value: &Value,
    dicts: &HashMap<String, Vec<DictEntry>>,
) -> Result<Value, String> {
    match value {
        Value::Op { op, args, saved } => {
            let args = args
                .iter()
                .map(|arg| resolve_dict_reporters(arg, dicts))
                .collect::<Result<Vec<_>, _>>()?;
            if is_dict_reporter(op) {
                let name: Box<str> = match op {
                    Op::Ext(name) => name.clone(),
                    _ => unreachable!("validated by is_dict_reporter"),
                };
                resolve_dict_reporter(&name, args, dicts)
            } else {
                Ok(Value::Op {
                    op: op.clone(),
                    args,
                    saved: saved.clone(),
                })
            }
        }
        Value::Call {
            block_id,
            args,
            branches,
            saved,
        } => Ok(Value::Call {
            block_id: block_id.clone(),
            args: args
                .iter()
                .map(|arg| resolve_dict_reporters(arg, dicts))
                .collect::<Result<Vec<_>, _>>()?,
            branches: branches.clone(),
            saved: saved.clone(),
        }),
        _ => Ok(value.clone()),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn dict_editor_state_round_trips_and_defaults_for_older_dicts() {
        let dict = DictDef {
            name: "save".to_string(),
            entries: vec![DictEntry {
                key: "hp".to_string(),
                value: DictItem::Number(3.0),
            }],
            editor_visible: true,
            editor_x: 12,
            editor_y: 34,
        };
        let json = serde_json::to_string(&dict).unwrap();
        let back: DictDef = serde_json::from_str(&json).unwrap();
        assert_eq!(dict, back);
        let legacy: DictDef = serde_json::from_str(r#"{"name":"old","entries":[]}"#).unwrap();
        assert!(!legacy.editor_visible);
        assert_eq!((legacy.editor_x, legacy.editor_y), (0, 0));
    }

    #[test]
    fn dict_set_replaces_and_dict_remove_reports() {
        let mut entries = vec![DictEntry {
            key: "a".to_string(),
            value: DictItem::Number(1.0),
        }];
        dict_set(&mut entries, "b".to_string(), DictItem::Text("x".into()));
        dict_set(&mut entries, "a".to_string(), DictItem::Number(2.0));
        assert_eq!(entries.len(), 2);
        assert_eq!(dict_lookup(&entries, "a"), Some(&DictItem::Number(2.0)));
        assert!(dict_remove(&mut entries, "a"));
        assert!(!dict_remove(&mut entries, "a"));
        assert_eq!(entries.len(), 1);
    }

    #[test]
    fn dict_json_round_trips_flat_objects() {
        let entries = vec![
            DictEntry { key: "hp".to_string(), value: DictItem::Number(3.0) },
            DictEntry { key: "name".to_string(), value: DictItem::Text("fi\"sh".into()) },
        ];
        let json = dict_to_json(&entries);
        assert_eq!(json, r#"{"hp":3.0,"name":"fi\"sh"}"#);
        assert_eq!(parse_json_object(&json).unwrap(), entries);
        assert!(parse_json_object("[1,2]").is_err());
        assert!(parse_json_object(r#"{"a":true}"#).is_err());
        assert!(parse_json_object(r#"{"a":{"b":1}}"#).is_err());
        assert!(parse_json_object("nope").is_err());
    }

    #[test]
    fn resolve_dict_reporters_reads_values_and_keys() {
        use crate::value::Value;
        let dicts = HashMap::from([(
            "save".to_string(),
            vec![DictEntry { key: "hp".to_string(), value: DictItem::Number(3.0) }],
        )]);
        let value = Value::Op {
            op: Op::from_name("DictValue"),
            args: vec![Value::text("hp"), Value::text("save")],
            saved: Box::new(Value::number(0.0)),
        };
        assert_eq!(
            resolve_dict_reporters(&value, &dicts).and_then(|value| value.eval_text()),
            Ok("3".to_string())
        );
        let missing = Value::Op {
            op: Op::from_name("DictValue"),
            args: vec![Value::text("mp"), Value::text("save")],
            saved: Box::new(Value::number(0.0)),
        };
        assert_eq!(
            resolve_dict_reporters(&missing, &dicts).and_then(|value| value.eval_text()),
            Ok(String::new())
        );
    }

    #[test]
    fn rename_dict_in_value_only_touches_reporter_name_args() {
        let mut value = Value::Op {
            op: Op::from_name("DictValue"),
            args: vec![Value::text("hp"), Value::text("old")],
            saved: Box::new(Value::number(0.0)),
        };
        rename_dict_in_value(&mut value, "old", "new");
        assert_eq!(
            value,
            Value::Op {
                op: Op::from_name("DictValue"),
                args: vec![Value::text("hp"), Value::text("new")],
                saved: Box::new(Value::number(0.0)),
            }
        );
    }
}
