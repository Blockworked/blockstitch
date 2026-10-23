//! C ABI over blockstitch-core. A host opens a session (one document plus
//! its history), sends JSON commands, and frees every string it gets back.
//!
//! Ownership: input strings are borrowed for the call only; output strings
//! are allocated here and must go back through `bs_string_free`.
//! Not thread-safe: a session must be used from one thread at a time.

use std::cell::RefCell;
use std::collections::HashMap;
use std::ffi::{CStr, CString, c_char};

use blockstitch_core::editor::{History, ValueLocation};
use blockstitch_core::graph::{BlockGraph, BlockKind, InputValueType, Instruction};
use blockstitch_core::value::Value;
use serde::{Deserialize, Serialize};
use serde_json::{Value as Json, json};

/// Bumped whenever a signature or the command/response shape changes.
pub const ABI_VERSION: u32 = 1;

/// A stand-in vocabulary until a headless host vocabulary exists.
#[derive(Debug, Clone, PartialEq, Hash, Serialize, Deserialize)]
pub enum Block {
    Start,
    Say { message: Value },
    Repeat { count: Value, body: Vec<Instruction<Block>> },
}

impl BlockKind for Block {
    fn visit_values_mut(&mut self, f: &mut dyn FnMut(&mut Value, InputValueType)) {
        match self {
            Block::Say { message } => f(message, InputValueType::Any),
            Block::Repeat { count, .. } => f(count, InputValueType::Any),
            Block::Start => {}
        }
    }
    fn is_header(&self) -> bool {
        matches!(self, Block::Start)
    }
    fn body(&self, slot: u8) -> Option<&Vec<Instruction<Block>>> {
        match (self, slot) {
            (Block::Repeat { body, .. }, 0) => Some(body),
            _ => None,
        }
    }
    fn body_mut(&mut self, slot: u8) -> Option<&mut Vec<Instruction<Block>>> {
        match (self, slot) {
            (Block::Repeat { body, .. }, 0) => Some(body),
            _ => None,
        }
    }
    fn value_slot_mut(&mut self, field: &str) -> Option<&mut Value> {
        match (self, field) {
            (Block::Say { message }, "message") => Some(message),
            (Block::Repeat { count, .. }, "count") => Some(count),
            _ => None,
        }
    }
    fn field_requires_integer(&self, field: &str) -> bool {
        matches!((self, field), (Block::Repeat { .. }, "count"))
    }
}

struct Session {
    graph: BlockGraph<Block>,
    history: History<BlockGraph<Block>>,
}

thread_local! {
    static SESSIONS: RefCell<HashMap<u32, Session>> = RefCell::new(HashMap::new());
    static NEXT: RefCell<u32> = const { RefCell::new(1) };
}

#[derive(Deserialize)]
struct Command {
    command: String,
    #[serde(default)]
    args: Json,
}

fn arg<T: for<'de> Deserialize<'de>>(args: &Json, key: &str) -> Result<T, String> {
    serde_json::from_value(args.get(key).cloned().unwrap_or(Json::Null))
        .map_err(|e| format!("bad `{key}`: {e}"))
}

/// Runs one command. `Ok` carries the result; an edit that changes nothing
/// pushes no undo step.
fn run(session: &mut Session, command: &Command) -> Result<Json, String> {
    let args = &command.args;
    let before = session.graph.clone();
    let result = match command.command.as_str() {
        "snapshot" => return serde_json::to_value(&session.graph).map_err(|e| e.to_string()),
        "evaluate" => {
            let value: Value = arg(args, "value")?;
            return value.eval().map(|v| json!(v)).map_err(|e| e);
        }
        "undo" | "redo" => {
            let current = session.graph.clone();
            let next = if command.command == "undo" {
                session.history.undo(current)
            } else {
                session.history.redo(current)
            };
            let changed = next.is_some();
            if let Some(graph) = next {
                session.graph = graph;
            }
            return Ok(json!({ "changed": changed }));
        }
        "add_strand" => {
            let x: i32 = arg(args, "x")?;
            let y: i32 = arg(args, "y")?;
            let kinds: Vec<Block> = arg(args, "instructions")?;
            let id = session.graph.add_strand(x, y, kinds.into_iter().map(Instruction::new).collect());
            json!({ "strand_id": id })
        }
        "edit_value_field" => {
            let location: ValueLocation = arg(args, "location")?;
            let text: String = arg(args, "text")?;
            json!(format!("{:?}", session.graph.edit_value_text(&location, text)))
        }
        "put_value" => {
            let location: ValueLocation = arg(args, "location")?;
            let value: Value = arg(args, "value")?;
            if !session.graph.put_value(&location, value) {
                return Err("no value at that location".into());
            }
            Json::Null
        }
        "__panic" if cfg!(feature = "panic-probe") => panic!("probe"),
        other => return Err(format!("unsupported command `{other}`")),
    };
    if session.graph != before {
        session.history.push(before);
    }
    Ok(result)
}

fn respond(result: Result<Json, String>) -> *mut c_char {
    let body = match result {
        Ok(result) => json!({ "ok": true, "result": result, "error": null }),
        Err(error) => json!({ "ok": false, "result": null, "error": error }),
    };
    CString::new(body.to_string()).unwrap_or_default().into_raw()
}

#[unsafe(no_mangle)]
pub extern "C" fn bs_abi_version() -> u32 {
    ABI_VERSION
}

/// Opens an empty document. Never returns 0.
#[unsafe(no_mangle)]
pub extern "C" fn bs_session_new() -> u32 {
    let handle = NEXT.with(|n| {
        let mut n = n.borrow_mut();
        let h = *n;
        *n += 1;
        h
    });
    let session = Session { graph: BlockGraph::new(), history: History::new(100) };
    SESSIONS.with(|s| s.borrow_mut().insert(handle, session));
    handle
}

#[unsafe(no_mangle)]
pub extern "C" fn bs_session_free(handle: u32) {
    SESSIONS.with(|s| s.borrow_mut().remove(&handle));
}

/// Runs a `{"command": ..., "args": {...}}` line against a session and
/// answers `{"ok", "result", "error"}`. Free the answer with `bs_string_free`.
///
/// # Safety
/// `command` must be a valid NUL-terminated string.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn bs_dispatch(handle: u32, command: *const c_char) -> *mut c_char {
    if command.is_null() {
        return respond(Err("null command".into()));
    }
    let text = unsafe { CStr::from_ptr(command) }.to_string_lossy();
    let parsed: Command = match serde_json::from_str(&text) {
        Ok(c) => c,
        Err(e) => return respond(Err(format!("bad command: {e}"))),
    };
    // A panic must not unwind into C++. Where unwinding exists it becomes an
    // error answer; the web build is panic=abort, so there it ends the page.
    let answer = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        SESSIONS.with(|s| match s.borrow_mut().get_mut(&handle) {
            Some(session) => run(session, &parsed),
            None => Err(format!("no session {handle}")),
        })
    }));
    respond(answer.unwrap_or_else(|_| Err("the core panicked".into())))
}

/// # Safety
/// `text` must come from this library and not have been freed.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn bs_string_free(text: *mut c_char) {
    if !text.is_null() {
        drop(unsafe { CString::from_raw(text) });
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn call(h: u32, line: &str) -> Json {
        let c = CString::new(line).unwrap();
        let out = unsafe { bs_dispatch(h, c.as_ptr()) };
        let text = unsafe { CStr::from_ptr(out) }.to_str().unwrap().to_owned();
        unsafe { bs_string_free(out) };
        serde_json::from_str(&text).unwrap()
    }

    #[test]
    fn edit_and_undo() {
        let h = bs_session_new();
        let r = call(h, r#"{"command":"add_strand","args":{"x":0,"y":0,"instructions":["Start",{"Say":{"message":{"kind":"Number","value":1}}}]}}"#);
        let strand = r["result"]["strand_id"].as_str().unwrap().to_owned();
        let edit = format!(
            r#"{{"command":"edit_value_field","args":{{"location":{{"kind":"Field","strand_id":"{strand}","index":[{{"index":1}}],"field_id":"message","path":[]}},"text":"42"}}}}"#
        );
        assert_eq!(call(h, &edit)["ok"], true);
        let snap = call(h, r#"{"command":"snapshot"}"#);
        assert_eq!(snap["result"]["strands"][0]["instructions"][1]["kind"]["Say"]["message"]["value"], 42.0);
        assert_eq!(call(h, r#"{"command":"undo"}"#)["result"]["changed"], true);
        let snap = call(h, r#"{"command":"snapshot"}"#);
        assert_eq!(snap["result"]["strands"][0]["instructions"][1]["kind"]["Say"]["message"]["value"], 1.0);
        assert_eq!(call(h, r#"{"command":"nope"}"#)["ok"], false);
        bs_session_free(h);
    }
}
