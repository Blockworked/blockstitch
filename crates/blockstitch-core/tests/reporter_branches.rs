//! Edits inside a custom reporter's branch go through a temporary strand.

use blockstitch_core::editor::{
    EditCommand, EditContext, PathStep, REPORTER_BRANCH_PREFIX, ValueLocation, reporter_branch_ids,
};
use blockstitch_core::graph::{BlockGraph, BlockKind, InputValueType, Instruction};
use blockstitch_core::value::Value;
use serde::{Deserialize, Serialize};
use serde_json::{Value as Json, json};

#[derive(Debug, Clone, PartialEq, Hash, Serialize, Deserialize)]
#[serde(tag = "type")]
enum Block {
    Start,
    Say { text: Value },
}

impl BlockKind for Block {
    fn visit_values_mut(&mut self, f: &mut dyn FnMut(&mut Value, InputValueType)) {
        if let Block::Say { text } = self {
            f(text, InputValueType::Any);
        }
    }
    fn is_header(&self) -> bool {
        matches!(self, Block::Start)
    }
    fn value_slot_mut(&mut self, field: &str) -> Option<&mut Value> {
        match (self, field) {
            (Block::Say { text }, "SayText") => Some(text),
            _ => None,
        }
    }
}

fn read(body: &[Json]) -> Result<Vec<Instruction<Block>>, String> {
    body.iter()
        .map(|b| serde_json::from_value(b.clone()).map_err(|e| e.to_string()))
        .collect()
}

fn write(instruction: &Instruction<Block>) -> Result<Json, String> {
    serde_json::to_value(instruction).map_err(|e| e.to_string())
}

fn reporter() -> Value {
    Value::Call {
        block_id: "r".into(),
        args: vec![],
        branches: vec![],
        saved: Box::new(Value::number(0.0)),
    }
}

#[test]
fn an_insert_into_a_branch_lands_in_the_reporter() {
    let mut graph: BlockGraph<Block> = BlockGraph::new();
    let strand = graph.add_strand(
        0,
        0,
        vec![Instruction::new(Block::Say { text: reporter() })],
    );
    let location = ValueLocation::Field {
        strand_id: strand.clone(),
        index: vec![PathStep::at(0)],
        field_id: "SayText".into(),
        path: vec![],
    };
    let branch = format!(
        "{REPORTER_BRANCH_PREFIX}{}",
        json!({ "location": location, "slot": 0 })
    );
    let args = json!({ "strandId": branch, "path": [{ "index": 0 }] });
    let ids = reporter_branch_ids(&args);
    assert_eq!(ids, vec![branch.clone()]);

    let open = graph.open_reporter_branches(&ids, &read).unwrap();
    let said = Instruction::new(Block::Say {
        text: Value::text("hi"),
    });
    let insert = EditCommand::InsertInstruction {
        strand_id: branch.clone(),
        path: vec![PathStep::at(0)],
        instruction: said,
    };
    graph.apply_edit(insert, &EditContext::default()).unwrap();
    graph.close_reporter_branches(open, &write).unwrap();

    assert_eq!(graph.strands.len(), 1, "the temporary strand is gone");
    let Some(Value::Call { branches, .. }) = graph.value_at(&location) else {
        panic!("no reporter")
    };
    assert_eq!(branches[0].len(), 1);
    assert_eq!(branches[0][0]["kind"]["text"]["value"], "hi");
}

#[test]
fn a_header_in_a_branch_is_refused() {
    let mut graph: BlockGraph<Block> = BlockGraph::new();
    let strand = graph.add_strand(
        0,
        0,
        vec![Instruction::new(Block::Say { text: reporter() })],
    );
    let location = ValueLocation::Field {
        strand_id: strand,
        index: vec![PathStep::at(0)],
        field_id: "SayText".into(),
        path: vec![],
    };
    let branch = format!(
        "{REPORTER_BRANCH_PREFIX}{}",
        json!({ "location": location, "slot": 0 })
    );
    let open = graph
        .open_reporter_branches(&[branch.clone()], &read)
        .unwrap();
    graph
        .strands
        .iter_mut()
        .find(|s| s.id == branch)
        .unwrap()
        .instructions
        .push(Instruction::new(Block::Start));
    assert!(graph.close_reporter_branches(open, &write).is_err());
}
