// The ABI over a stand-in vocabulary: sessions, the envelope, typed edits
// with one undo step each, and the shared evaluator.
use std::ffi::{CStr, CString};
use std::ops::{Deref, DerefMut};

use blockstitch_core::editor::{EditCommand, EditContext, History};
use blockstitch_core::graph::{BlockGraph, BlockKind, InputValueType, Instruction};
use blockstitch_core::value::Value;
use blockstitch_ffi::{Host, arg, run_edit};
use serde::{Deserialize, Serialize};
use serde_json::{Value as Json, json};

#[derive(Debug, Clone, PartialEq, Hash, Serialize, Deserialize)]
enum Block {
    Start,
    Say { message: Value },
}

impl BlockKind for Block {
    fn visit_values_mut(&mut self, f: &mut dyn FnMut(&mut Value, InputValueType)) {
        if let Block::Say { message } = self {
            f(message, InputValueType::Any)
        }
    }
    fn is_header(&self) -> bool {
        matches!(self, Block::Start)
    }
    fn body(&self, _: u8) -> Option<&Vec<Instruction<Block>>> {
        None
    }
    fn body_mut(&mut self, _: u8) -> Option<&mut Vec<Instruction<Block>>> {
        None
    }
    fn value_slot_mut(&mut self, field: &str) -> Option<&mut Value> {
        match (self, field) {
            (Block::Say { message }, "message") => Some(message),
            _ => None,
        }
    }
}

#[derive(Default)]
struct Doc(BlockGraph<Block>);
impl Deref for Doc {
    type Target = BlockGraph<Block>;
    fn deref(&self) -> &Self::Target {
        &self.0
    }
}
impl DerefMut for Doc {
    fn deref_mut(&mut self) -> &mut Self::Target {
        &mut self.0
    }
}

struct Session {
    doc: Doc,
    history: History<BlockGraph<Block>>,
}

impl Default for Session {
    fn default() -> Self {
        Session { doc: Doc::default(), history: History::new(10) }
    }
}

impl Host for Session {
    fn dispatch(&mut self, command: &str, args: &Json) -> Result<Json, String> {
        match command {
            "snapshot" => serde_json::to_value(&*self.doc).map_err(|e| e.to_string()),
            "add_strand" => {
                let kinds: Vec<Block> = arg(args, "instructions")?;
                let id = self.doc.add_strand(0, 0, kinds.into_iter().map(Instruction::new).collect());
                Ok(json!(id))
            }
            "edit" => {
                let command: EditCommand<Block> = arg(args, "command")?;
                let ctx = EditContext::default();
                let outcome = run_edit(&mut self.doc, &mut self.history, |d| d.0.clone(), command, &ctx)
                    .map_err(String::from)?;
                Ok(json!({ "changed": outcome.changed }))
            }
            "undo" => {
                let previous = self.history.undo(self.doc.0.clone());
                let changed = previous.is_some();
                if let Some(graph) = previous {
                    self.doc.0 = graph;
                }
                Ok(json!(changed))
            }
            "evaluate" => {
                let value: Value = arg(args, "value")?;
                value.eval_text().map(Json::String)
            }
            "panic" => panic!("probe"),
            other => Err(format!("unsupported command `{other}`")),
        }
    }
}

blockstitch_ffi::export_abi!(Session);

fn call(h: u32, command: &str, args: Json) -> Json {
    let line = CString::new(json!({ "command": command, "args": args }).to_string()).unwrap();
    let out = unsafe { bs_dispatch(h, line.as_ptr()) };
    let text = unsafe { CStr::from_ptr(out) }.to_str().unwrap().to_owned();
    unsafe { bs_string_free(out) };
    serde_json::from_str(&text).unwrap()
}

fn say(h: u32) -> Json {
    call(h, "snapshot", Json::Null)["result"]["strands"][0]["instructions"][1]["kind"]["Say"]["message"].clone()
}

#[test]
fn typed_edits_and_undo_through_the_abi() {
    assert_eq!(bs_abi_version(), blockstitch_ffi::ABI_VERSION);
    let h = bs_session_new();
    let strand = call(h, "add_strand", json!({ "instructions": ["Start", { "Say": { "message": { "kind": "Number", "value": 1 } } }] }));
    let strand = strand["result"].as_str().unwrap().to_owned();
    let location = json!({ "kind": "Field", "strand_id": strand, "index": [{ "index": 1 }], "field_id": "message", "path": [] });
    let edit = |text: &str| call(h, "edit", json!({ "command": { "edit_field_text": { "location": location, "text": text } } }));
    assert_eq!(edit("4")["result"]["changed"], true);
    assert_eq!(edit("42")["result"]["changed"], true);
    assert_eq!(say(h)["value"], 42.0);
    // Keystrokes into one field are one step.
    assert_eq!(call(h, "undo", Json::Null)["result"], true);
    assert_eq!(say(h)["value"], 1.0);
    assert_eq!(call(h, "undo", Json::Null)["result"], false);
    // A missing location is an error and writes nothing.
    let missing = json!({ "edit_field_text": { "location": { "kind": "Floating", "floating_id": "nope", "path": [] }, "text": "1" } });
    assert_eq!(call(h, "edit", json!({ "command": missing }))["ok"], false);
    bs_session_free(h);
}

#[test]
fn envelope_errors_and_evaluation() {
    let h = bs_session_new();
    let r = call(h, "evaluate", json!({ "value": { "kind": "Op", "op": "Join", "args": [
        { "kind": "Text", "value": "héllo " }, { "kind": "Number", "value": 3 }] } }));
    assert_eq!(r, json!({ "ok": true, "result": "héllo 3", "error": null }));
    assert_eq!(call(h, "nope", Json::Null)["ok"], false);
    assert_eq!(call(h, "panic", Json::Null)["error"], "the core panicked");
    bs_session_free(h);
    assert_eq!(call(h, "snapshot", Json::Null)["error"], "no such session");
    let bad = CString::new("not json").unwrap();
    let out = unsafe { bs_dispatch(1, bad.as_ptr()) };
    assert!(unsafe { CStr::from_ptr(out) }.to_str().unwrap().contains("bad command"));
    unsafe { bs_string_free(out) };
}
