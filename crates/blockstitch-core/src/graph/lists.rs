//! Named, document-scoped lists: ordered collections of literal
//! number/text items, parallel to [`crate::graph::VariableDef`] but holding
//! many values instead of one. A host document owns them through
//! [`crate::graph::BlockGraph::lists`]; the reporter operators below
//! (`ListItem`, `ListLength`, ...) read them from a live [`ListStore`].

use crate::value::{Evaluated, Op, Value};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::sync::{Arc, Mutex};

/// Shared, document-wide list contents, parallel to a variable store: list
/// name to its current items. One `Arc` is shared across a run's threads so
/// a mutation in one strand is visible to the others.
pub type ListStore = Arc<Mutex<HashMap<String, Vec<ListItem>>>>;

/// A list item is deliberately a literal only: unlike an instruction field it
/// cannot contain an expression, variable, or custom-block call. This keeps a
/// saved list stable and makes the editor safe to edit directly.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(tag = "kind", content = "value")]
pub enum ListItem {
    Number(f64),
    Text(String),
}

impl ListItem {
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

impl std::hash::Hash for ListItem {
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

/// A named, document-scoped collection. Lists live alongside variables but
/// only hold literal number/text items (see [`ListItem`]).
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ListDef {
    pub name: String,
    #[serde(default)]
    pub items: Vec<ListItem>,
    /// Whether the editable list monitor is visible on the canvas. This is
    /// persisted with its document so reopening the app restores it.
    #[serde(default)]
    pub editor_visible: bool,
    /// Canvas position of the editable list monitor in CSS pixels.
    #[serde(default)]
    pub editor_x: i32,
    /// Canvas position of the editable list monitor in CSS pixels.
    #[serde(default)]
    pub editor_y: i32,
}

impl std::hash::Hash for ListDef {
    fn hash<H: std::hash::Hasher>(&self, state: &mut H) {
        self.name.hash(state);
        self.items.hash(state);
        self.editor_visible.hash(state);
        self.editor_x.hash(state);
        self.editor_y.hash(state);
    }
}

/// Arg index holding the list name for a list-reporter op, by wire name.
/// The name is the second arg except for `ListLength`/`ListContains`/
/// `ListIsEmpty`/`ListAsJson`, where it is the first.
pub fn list_reporter_name_index(op_name: &str) -> Option<usize> {
    match op_name {
        "ListItem" | "ListItemNumber" | "ListAmount" | "ListItemExists" => Some(1),
        "ListLength" | "ListContains" | "ListIsEmpty" | "ListAsJson" => Some(0),
        _ => None,
    }
}

/// True for a value-position list reporter (`Op::Ext` with a list wire
/// name) - resolved against the live lists, never by plain `Value::eval`.
pub fn is_list_reporter(op: &Op) -> bool {
    match op {
        Op::Ext(name) => list_reporter_name_index(name).is_some(),
        _ => false,
    }
}

/// Renames a list reference inside a value tree: a list reporter's name arg
/// (a plain `Text` leaf) plus every nested arg. Call args recurse too, since
/// a reporter can sit inside a custom-block call.
pub fn rename_list_in_value(value: &mut Value, old: &str, new: &str) {
    match value {
        Value::Op { op, args, saved } => {
            if let Op::Ext(name) = op
                && let Some(index) = list_reporter_name_index(name)
                && let Some(Value::Text { value: name_arg }) = args.get_mut(index)
                && name_arg == old
            {
                *name_arg = new.to_string();
            }
            for arg in args.iter_mut() {
                rename_list_in_value(arg, old, new);
            }
            rename_list_in_value(saved, old, new);
        }
        Value::Call {
            block_id: _,
            args,
            branches: _,
            saved,
        } => {
            for arg in args.iter_mut() {
                rename_list_in_value(arg, old, new);
            }
            rename_list_in_value(saved, old, new);
        }
        Value::Number { .. } | Value::Text { .. } | Value::Bool | Value::Var { .. } | Value::Param { .. } => {}
    }
}

/// Converts a Scratch-style 1-based numeric index to a vector offset. An
/// insert may target the slot immediately after the final item; other list
/// commands require an existing item.
pub fn list_index(value: f64, len: usize, allow_end: bool) -> Option<usize> {
    if !value.is_finite() || value < 1.0 {
        return None;
    }
    let index = value.floor() as usize - 1;
    if index < len || (allow_end && index == len) {
        Some(index)
    } else {
        None
    }
}

/// Resolves one list reporter whose arguments have already been reduced to
/// ordinary values. Shared by a host's runner and the editor's
/// click-to-preview evaluator so the two always agree about list semantics.
pub fn resolve_list_reporter(
    op_name: &str,
    args: Vec<Value>,
    lists: &HashMap<String, Vec<ListItem>>,
) -> Result<Value, String> {
    let text = |index: usize| {
        args.get(index)
            .ok_or_else(|| "missing list reporter argument".to_string())
            .and_then(Value::eval_text)
    };
    let number = |index: usize| {
        args.get(index)
            .ok_or_else(|| "missing list reporter argument".to_string())
            .and_then(Value::eval_number)
    };
    let list_name = match op_name {
        "ListItem" | "ListItemNumber" | "ListAmount" | "ListItemExists" => text(1)?,
        "ListContains" => text(0)?,
        "ListLength" | "ListIsEmpty" | "ListAsJson" => text(0)?,
        _ => return Err("not a list reporter".to_string()),
    };
    let list = lists.get(&list_name).cloned().unwrap_or_default();
    let evaluated = match op_name {
        "ListItem" => list_index(number(0)?, list.len(), false)
            .and_then(|index| list.get(index))
            .map(ListItem::evaluated)
            .unwrap_or(Evaluated::Text(String::new())),
        "ListItemNumber" => {
            let needle = ListItem::from_evaluated(args[0].eval()?)
                .ok_or_else(|| "list items must be number or text".to_string())?;
            Evaluated::Number(
                list.iter()
                    .position(|item| item == &needle)
                    .map_or(0, |index| index + 1) as f64,
            )
        }
        "ListAmount" => {
            let needle = ListItem::from_evaluated(args[0].eval()?)
                .ok_or_else(|| "list items must be number or text".to_string())?;
            Evaluated::Number(list.iter().filter(|item| *item == &needle).count() as f64)
        }
        "ListLength" => Evaluated::Number(list.len() as f64),
        "ListContains" => {
            let needle = ListItem::from_evaluated(args[1].eval()?)
                .ok_or_else(|| "list items must be number or text".to_string())?;
            Evaluated::Bool(list.contains(&needle))
        }
        "ListItemExists" => Evaluated::Bool(list_index(number(0)?, list.len(), false).is_some()),
        "ListIsEmpty" => Evaluated::Bool(list.is_empty()),
        "ListAsJson" => Evaluated::Text(list_to_json(&list)),
        _ => unreachable!("validated by is_list_reporter"),
    };
    Ok(evaluated.into_value())
}

/// Serializes list items as a JSON array, in order. Numbers stay numeric,
/// text is quoted - the inverse of [`parse_json_array`].
pub fn list_to_json(items: &[ListItem]) -> String {
    let mut out = String::from("[");
    for (index, item) in items.iter().enumerate() {
        if index > 0 {
            out.push(',');
        }
        match item {
            ListItem::Number(value) => {
                if value.is_finite() {
                    out.push_str(&serde_json::to_string(value).unwrap_or_else(|_| "null".to_string()));
                } else {
                    out.push_str("null");
                }
            }
            ListItem::Text(value) => {
                out.push_str(&serde_json::to_string(value).unwrap_or_else(|_| "\"\"".to_string()))
            }
        }
    }
    out.push(']');
    out
}

/// Parses a JSON array into list items, in order. Only numbers and strings
/// are valid elements - anything else (booleans, null, nested objects or
/// arrays) is an error naming the offending position.
pub fn parse_json_array(text: &str) -> Result<Vec<ListItem>, String> {
    let json: serde_json::Value =
        serde_json::from_str(text).map_err(|_| "that text isn't a JSON array".to_string())?;
    let serde_json::Value::Array(elements) = json else {
        return Err("that text isn't a JSON array".to_string());
    };
    elements
        .into_iter()
        .enumerate()
        .map(|(index, json)| match json {
            serde_json::Value::Number(value) => value
                .as_f64()
                .map(ListItem::Number)
                .ok_or_else(|| format!("item {} isn't a number or text", index + 1)),
            serde_json::Value::String(value) => Ok(ListItem::Text(value)),
            _ => Err(format!("item {} isn't a number or text", index + 1)),
        })
        .collect()
}

/// Replaces list reporter nodes with their values from `lists`, without
/// executing custom-block calls. Useful for non-running contexts such as a
/// canvas reporter preview; a host's full runner adds call/parameter
/// resolution on top.
pub fn resolve_list_reporters(
    value: &Value,
    lists: &HashMap<String, Vec<ListItem>>,
) -> Result<Value, String> {
    match value {
        Value::Op { op, args, saved } => {
            let args = args
                .iter()
                .map(|arg| resolve_list_reporters(arg, lists))
                .collect::<Result<Vec<_>, _>>()?;
            if is_list_reporter(op) {
                let name: Box<str> = match op {
                    Op::Ext(name) => name.clone(),
                    _ => unreachable!("validated by is_list_reporter"),
                };
                resolve_list_reporter(&name, args, lists)
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
                .map(|arg| resolve_list_reporters(arg, lists))
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
    fn list_editor_state_round_trips_and_defaults_for_older_lists() {
        let list = ListDef {
            name: "items".to_string(),
            items: vec![ListItem::Number(1.0)],
            editor_visible: true,
            editor_x: 12,
            editor_y: 34,
        };
        let json = serde_json::to_string(&list).unwrap();
        let back: ListDef = serde_json::from_str(&json).unwrap();
        assert_eq!(list, back);
        let legacy: ListDef = serde_json::from_str(r#"{"name":"old","items":[]}"#).unwrap();
        assert!(!legacy.editor_visible);
        assert_eq!((legacy.editor_x, legacy.editor_y), (0, 0));
    }

    #[test]
    fn list_index_is_one_based_with_optional_end_slot() {
        assert_eq!(list_index(1.0, 3, false), Some(0));
        assert_eq!(list_index(3.0, 3, false), Some(2));
        assert_eq!(list_index(4.0, 3, false), None);
        assert_eq!(list_index(4.0, 3, true), Some(3));
        assert_eq!(list_index(0.0, 3, true), None);
        assert_eq!(list_index(f64::NAN, 3, true), None);
    }

    #[test]
    fn resolve_list_reporters_reads_items_and_length() {
        use crate::value::Value;
        let lists = HashMap::from([(
            "items".to_string(),
            vec![ListItem::Text("first".into()), ListItem::Number(7.0)],
        )]);
        let item = Value::Op {
            op: Op::from_name("ListItem"),
            args: vec![Value::number(2.0), Value::text("items")],
            saved: Box::new(Value::number(0.0)),
        };
        assert_eq!(
            resolve_list_reporters(&item, &lists).and_then(|value| value.eval_text()),
            Ok("7".to_string())
        );
        let length = Value::Op {
            op: Op::from_name("ListLength"),
            args: vec![Value::text("items")],
            saved: Box::new(Value::number(0.0)),
        };
        assert_eq!(
            resolve_list_reporters(&length, &lists).and_then(|value| value.eval_text()),
            Ok("2".to_string())
        );
    }

    #[test]
    fn list_json_round_trips_flat_arrays() {
        let items = vec![ListItem::Number(2.0), ListItem::Text("a\"b".into())];
        let json = list_to_json(&items);
        assert_eq!(json, r#"[2.0,"a\"b"]"#);
        assert_eq!(parse_json_array(&json).unwrap(), items);
        assert!(parse_json_array(r#"{"a":1}"#).is_err());
        assert!(parse_json_array("[true]").is_err());
        assert!(parse_json_array("[null]").is_err());
        assert!(parse_json_array("[[1]]").is_err());
        assert!(parse_json_array("nope").is_err());
    }

    #[test]
    fn rename_list_in_value_only_touches_reporter_name_args() {
        let mut value = Value::Op {
            op: Op::from_name("ListItem"),
            args: vec![Value::number(1.0), Value::text("old")],
            saved: Box::new(Value::number(0.0)),
        };
        rename_list_in_value(&mut value, "old", "new");
        assert_eq!(
            value,
            Value::Op {
                op: Op::from_name("ListItem"),
                args: vec![Value::number(1.0), Value::text("new")],
                saved: Box::new(Value::number(0.0)),
            }
        );
    }
}
