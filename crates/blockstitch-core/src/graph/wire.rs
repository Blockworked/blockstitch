//! The frontend's shape for instructions. A document stores one as
//! `{"id": _, "kind": {...}}`; the canvas wants the flat `{"id": _, ...}` a
//! block node is. [`to_frontend`] and [`from_frontend`] switch between the
//! two at every [`Instruction`] the value holds, found by its type rather
//! than by how the JSON looks, so any other object (a plugin's payload, a
//! host's own `{id, type}` record) passes through unchanged.
//!
//! The flat shape needs a kind that serializes as a JSON object without an
//! `id` field of its own - an internally tagged enum, say. Anything else is
//! an error rather than a silently mixed shape.

use crate::graph::Instruction;
use serde::de::DeserializeOwned;
use serde::{Deserialize, Serialize};
use serde_json::{Map, Value};
use std::cell::Cell;

thread_local! {
    static FLAT: Cell<usize> = const { Cell::new(0) };
}

/// Marks this thread as encoding the frontend shape until dropped.
struct FlatScope;

impl FlatScope {
    fn enter() -> Self {
        FLAT.with(|depth| depth.set(depth.get() + 1));
        FlatScope
    }
}

impl Drop for FlatScope {
    fn drop(&mut self) {
        FLAT.with(|depth| depth.set(depth.get() - 1));
    }
}

/// True while [`to_frontend`] or [`from_frontend`] runs on this thread.
pub(crate) fn flat() -> bool {
    FLAT.with(|depth| depth.get() > 0)
}

/// Serializes `value` with every instruction in it flattened.
pub fn to_frontend<T: Serialize + ?Sized>(value: &T) -> Result<Value, serde_json::Error> {
    let _scope = FlatScope::enter();
    serde_json::to_value(value)
}

/// Deserializes `json`, reading every instruction position as the flat
/// shape. The stored `{id, kind}` shape and a bare kind (a fresh id) are
/// accepted too.
pub fn from_frontend<T: DeserializeOwned>(json: Value) -> Result<T, serde_json::Error> {
    let _scope = FlatScope::enter();
    serde_json::from_value(json)
}

/// `{"id": id, ...kind}`. Nested instructions inside `kind` flatten too,
/// since the scope is still open.
pub(crate) fn flatten<K: Serialize>(id: &str, kind: &K) -> Result<Value, String> {
    let fields = match serde_json::to_value(kind).map_err(|e| e.to_string())? {
        Value::Object(fields) => fields,
        other => {
            return Err(format!(
                "an instruction kind must serialize as an object to be flattened, not {other}"
            ));
        }
    };
    if fields.contains_key("id") {
        return Err("an instruction kind can't have its own \"id\" field".to_string());
    }
    let mut out = Map::with_capacity(fields.len() + 1);
    out.insert("id".to_string(), Value::String(id.to_string()));
    out.extend(fields);
    Ok(Value::Object(out))
}

/// The inverse of [`flatten`].
pub(crate) fn unflatten<'de, K: Deserialize<'de>>(json: Value) -> Result<Instruction<K>, String> {
    let mut map = match json {
        Value::Object(map) => map,
        other => {
            let kind = K::deserialize(other).map_err(|e| e.to_string())?;
            return Ok(Instruction::new(kind));
        }
    };
    let id = match map.remove("id") {
        None => None,
        Some(Value::String(id)) => Some(id),
        Some(other) => return Err(format!("an instruction id must be a string, not {other}")),
    };
    let finish = |kind| match &id {
        Some(id) => Instruction {
            id: id.clone(),
            kind,
        },
        None => Instruction::new(kind),
    };
    // The stored shape, kept for callers that send it.
    let stored = (map.len() == 1 && map.get("kind").is_some_and(Value::is_object))
        .then(|| map.get("kind").cloned())
        .flatten();
    match K::deserialize(Value::Object(map)) {
        Ok(kind) => Ok(finish(kind)),
        Err(flat_error) => match stored {
            Some(kind) => K::deserialize(kind)
                .map(finish)
                .map_err(|_| flat_error.to_string()),
            None => Err(flat_error.to_string()),
        },
    }
}
