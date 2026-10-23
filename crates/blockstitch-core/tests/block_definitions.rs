//! Editing a custom block's definition: call sites follow inputs and branches
//! by piece id wherever they're nested, and bad definitions are refused.

use blockstitch_core::graph::{
    BlockDef, BlockGraph, BlockKind, BlockPiece, BlockShape, InputValueType, Instruction,
};
use blockstitch_core::value::{Evaluated, Value};
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, PartialEq, Hash, Serialize, Deserialize)]
enum Block {
    Header(String),
    Say(Value),
    Repeat {
        count: Value,
        body: Vec<Instruction<Block>>,
    },
    Call {
        block_id: String,
        args: Vec<Value>,
        branches: Vec<Vec<Instruction<Block>>>,
    },
}

impl BlockKind for Block {
    const BODY_SLOTS: u8 = 8;

    fn visit_values_mut(&mut self, f: &mut dyn FnMut(&mut Value, InputValueType)) {
        match self {
            Block::Say(v) => f(v, InputValueType::Any),
            Block::Repeat { count, .. } => f(count, InputValueType::Any),
            Block::Call { args, .. } => args.iter_mut().for_each(|a| f(a, InputValueType::Any)),
            Block::Header(_) => {}
        }
    }
    fn is_header(&self) -> bool {
        matches!(self, Block::Header(_))
    }
    fn body(&self, slot: u8) -> Option<&Vec<Instruction<Block>>> {
        match (self, slot) {
            (Block::Repeat { body, .. }, 0) => Some(body),
            (Block::Call { branches, .. }, slot) => branches.get(slot as usize),
            _ => None,
        }
    }
    fn body_mut(&mut self, slot: u8) -> Option<&mut Vec<Instruction<Block>>> {
        match (self, slot) {
            (Block::Repeat { body, .. }, 0) => Some(body),
            (Block::Call { branches, .. }, slot) => branches.get_mut(slot as usize),
            _ => None,
        }
    }
    fn calls_block(&self, id: &str) -> bool {
        matches!(self, Block::Call { block_id, .. } if block_id == id)
    }
    fn call_args_mut(&mut self, id: &str) -> Option<&mut Vec<Value>> {
        match self {
            Block::Call { block_id, args, .. } if block_id == id => Some(args),
            _ => None,
        }
    }
    fn call_branches_mut(&mut self, id: &str) -> Option<&mut Vec<Vec<Instruction<Block>>>> {
        match self {
            Block::Call {
                block_id, branches, ..
            } if block_id == id => Some(branches),
            _ => None,
        }
    }
    fn block_header_id(&self) -> Option<&str> {
        match self {
            Block::Header(id) => Some(id),
            _ => None,
        }
    }
}

fn label(id: &str, text: &str) -> BlockPiece {
    BlockPiece::Label {
        id: id.into(),
        text: text.into(),
    }
}
fn input(id: &str, name: &str) -> BlockPiece {
    BlockPiece::Input {
        id: id.into(),
        name: name.into(),
        value_type: InputValueType::Any,
        default_value: None,
    }
}
fn branch(id: &str, name: &str) -> BlockPiece {
    BlockPiece::Branch {
        id: id.into(),
        name: name.into(),
    }
}
fn say(text: &str) -> Instruction<Block> {
    Instruction::new(Block::Say(Value::text(text)))
}
fn call(
    block_id: &str,
    args: Vec<Value>,
    branches: Vec<Vec<Instruction<Block>>>,
) -> Instruction<Block> {
    Instruction::new(Block::Call {
        block_id: block_id.into(),
        args,
        branches,
    })
}
fn reporter(block_id: &str, args: Vec<Value>) -> Value {
    Value::Call {
        block_id: block_id.into(),
        args,
        branches: vec![],
        saved: Box::new(Value::number(0.0)),
    }
}

fn make(g: &mut BlockGraph<Block>, pieces: Vec<BlockPiece>, shape: BlockShape) -> String {
    BlockDef::validate_pieces(&pieces).unwrap();
    g.create_block(pieces, shape, "#4C97FF".into(), 0, 0, |id| {
        Block::Header(id.into())
    })
}

fn args_of(ins: &Instruction<Block>) -> &Vec<Value> {
    match &ins.kind {
        Block::Call { args, .. } => args,
        other => panic!("not a call: {other:?}"),
    }
}

/// A call nested in a repeat, with a reporter call of the same block in one
/// of its own arguments.
fn nested_caller(g: &mut BlockGraph<Block>, id: &str) {
    let inner = reporter(id, vec![Value::number(7.0), Value::text("b")]);
    let caller = call(id, vec![Value::number(1.0), inner], vec![]);
    let repeat = Instruction::new(Block::Repeat {
        count: Value::number(2.0),
        body: vec![caller],
    });
    g.add_strand(0, 0, vec![repeat]);
}

fn nested_call(g: &BlockGraph<Block>) -> &Instruction<Block> {
    let strand = g
        .strands
        .iter()
        .find(|s| matches!(s.instructions[0].kind, Block::Repeat { .. }))
        .unwrap();
    let Block::Repeat { body, .. } = &strand.instructions[0].kind else {
        unreachable!()
    };
    &body[0]
}

#[test]
fn rename_reorder_and_remove_follow_input_ids_into_nested_calls() {
    let mut g = BlockGraph::new();
    let id = make(
        &mut g,
        vec![label("l", "move"), input("a", "x"), input("b", "y")],
        BlockShape::Normal,
    );
    nested_caller(&mut g, &id);

    // Rename and swap: values move with their piece id, not their position.
    g.update_block(
        &id,
        vec![label("l", "move"), input("b", "height"), input("a", "x")],
        BlockShape::Normal,
        "#4C97FF",
    )
    .unwrap();
    let args = args_of(nested_call(&g));
    assert_eq!(args[1], Value::number(1.0));
    let Value::Call { args: inner, .. } = &args[0] else {
        panic!("the reporter call moved with input b")
    };
    assert_eq!(inner, &vec![Value::text("b"), Value::number(7.0)]);

    // Removing one drops only its argument, everywhere.
    g.update_block(
        &id,
        vec![label("l", "move"), input("a", "x")],
        BlockShape::Normal,
        "#4C97FF",
    )
    .unwrap();
    assert_eq!(args_of(nested_call(&g)), &vec![Value::number(1.0)]);
}

#[test]
fn a_new_input_takes_its_default_at_existing_calls() {
    let mut g = BlockGraph::new();
    let id = make(&mut g, vec![label("l", "go")], BlockShape::Normal);
    g.add_strand(0, 0, vec![call(&id, vec![], vec![])]);
    let with_default = BlockPiece::Input {
        id: "n".into(),
        name: "speed".into(),
        value_type: InputValueType::Any,
        default_value: Some(Evaluated::Number(4.0)),
    };
    let flag = BlockPiece::Input {
        id: "f".into(),
        name: "fast".into(),
        value_type: InputValueType::Bool,
        default_value: None,
    };
    g.update_block(
        &id,
        vec![label("l", "go"), with_default, flag],
        BlockShape::Normal,
        "#4C97FF",
    )
    .unwrap();
    let strand = g
        .strands
        .iter()
        .find(|s| matches!(s.instructions[0].kind, Block::Call { .. }))
        .unwrap();
    assert_eq!(
        args_of(&strand.instructions[0]),
        &vec![Value::number(4.0), Value::Bool]
    );
}

#[test]
fn branch_bodies_stay_with_their_branch() {
    let mut g = BlockGraph::new();
    let id = make(
        &mut g,
        vec![
            label("l", "either"),
            branch("p", "first"),
            branch("q", "second"),
        ],
        BlockShape::Normal,
    );
    // One call at the top, one inside the other's first branch.
    let inner = call(
        &id,
        vec![],
        vec![vec![say("inner p")], vec![say("inner q")]],
    );
    g.add_strand(
        0,
        0,
        vec![call(
            &id,
            vec![],
            vec![vec![inner, say("p")], vec![say("q")]],
        )],
    );
    let floating = Value::Call {
        block_id: id.clone(),
        args: vec![],
        branches: vec![vec![serde_json::json!("p")], vec![serde_json::json!("q")]],
        saved: Box::new(Value::number(0.0)),
    };
    g.add_floating_value(0, 0, floating, None);

    g.update_block(
        &id,
        vec![
            label("l", "either"),
            branch("q", "second"),
            branch("p", "first"),
        ],
        BlockShape::Normal,
        "#4C97FF",
    )
    .unwrap();
    let top = &g
        .strands
        .iter()
        .find(|s| matches!(s.instructions[0].kind, Block::Call { .. }))
        .unwrap()
        .instructions[0];
    let Block::Call { branches, .. } = &top.kind else {
        unreachable!()
    };
    assert_eq!(branches[0], vec![say("q")]);
    assert_eq!(branches[1].len(), 2);
    let Block::Call {
        branches: inner, ..
    } = &branches[1][0].kind
    else {
        panic!("nested call stays put")
    };
    assert_eq!(inner, &vec![vec![say("inner q")], vec![say("inner p")]]);
    let Value::Call {
        branches: value_branches,
        ..
    } = &g.floating_values[0].value
    else {
        unreachable!()
    };
    assert_eq!(value_branches[0], vec![serde_json::json!("q")]);

    // Removing a branch drops its body; adding one starts empty.
    g.update_block(
        &id,
        vec![
            label("l", "either"),
            branch("p", "first"),
            branch("r", "third"),
        ],
        BlockShape::Normal,
        "#4C97FF",
    )
    .unwrap();
    let top = &g
        .strands
        .iter()
        .find(|s| matches!(s.instructions[0].kind, Block::Call { .. }))
        .unwrap()
        .instructions[0];
    let Block::Call { branches, .. } = &top.kind else {
        unreachable!()
    };
    assert_eq!(branches.len(), 2);
    assert_eq!(branches[0].len(), 2);
    assert!(branches[1].is_empty());
}

#[test]
fn reporter_shapes_and_bad_definitions() {
    let mut g = BlockGraph::new();
    let id = make(&mut g, vec![label("l", "ready")], BlockShape::ReturnsBool);
    assert_eq!(g.block_def(&id).unwrap().shape, BlockShape::ReturnsBool);
    g.update_block(
        &id,
        vec![label("l", "ready")],
        BlockShape::ReturnsValue,
        "#ff6680",
    )
    .unwrap();
    let def = g.block_def(&id).unwrap();
    assert_eq!(def.shape, BlockShape::ReturnsValue);
    assert_eq!(def.color, "#FF6680");

    let before = g.clone();
    let rejected = [
        vec![input("a", "x")],                                     // no name
        vec![label("l", "go"), input("a", "x"), input("b", "x")],  // duplicate input
        vec![label("l", "go"), input("a", "x"), branch("b", "x")], // branch shares the pool
        vec![label("l", "go"), input("a", " ")],                   // blank input
        vec![
            label("l", "go"),
            BlockPiece::Input {
                id: "a".into(),
                name: "x".into(),
                value_type: InputValueType::Bool,
                default_value: Some(Evaluated::Number(1.0)),
            },
        ], // wrong default type
        vec![
            label("l", "go"),
            BlockPiece::Input {
                id: "a".into(),
                name: "x".into(),
                value_type: InputValueType::Any,
                default_value: Some(Evaluated::Number(f64::INFINITY)),
            },
        ], // not finite
    ];
    for pieces in rejected {
        assert!(
            g.update_block(&id, pieces.clone(), BlockShape::Normal, "#4C97FF")
                .is_err(),
            "{pieces:?}"
        );
    }
    assert!(
        g.update_block(&id, vec![label("l", "go")], BlockShape::Normal, "blue")
            .is_err()
    );
    assert!(g == before, "a refused edit changes nothing");
}

#[test]
fn details_are_kept_by_a_prototype_edit() {
    let mut g = BlockGraph::new();
    let id = make(&mut g, vec![label("l", "go")], BlockShape::Normal);
    g.set_block_details(&id, " ALICE_GO ", " Goes. ", "rocket")
        .unwrap();
    g.update_block(
        &id,
        vec![label("l", "go now")],
        BlockShape::Ending,
        "#4C97FF",
    )
    .unwrap();
    let def = g.block_def(&id).unwrap();
    assert_eq!(
        (
            def.identifier.as_str(),
            def.description.as_str(),
            def.icon.as_str()
        ),
        ("ALICE_GO", "Goes.", "rocket")
    );
    g.set_block_details(&id, "", "", "Not An Icon").unwrap();
    assert_eq!(g.block_def(&id).unwrap().icon, "");
}
