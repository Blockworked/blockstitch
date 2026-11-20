//! Part blocks only stack with parts, inside a body that takes them.

use blockstitch_core::editor::PathStep;
use blockstitch_core::graph::{
    BlockGraph, BlockKind, Connector, Fragment, InputValueType, Instruction,
};
use blockstitch_core::value::Value;
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, PartialEq, Hash, Serialize, Deserialize)]
enum Block {
    Start,
    Say,
    Window(Vec<Instruction<Block>>),
    Label,
    Button(Vec<Instruction<Block>>),
}

impl BlockKind for Block {
    const PART_LABEL: &'static str = "window part";
    fn visit_values_mut(&mut self, _f: &mut dyn FnMut(&mut Value, InputValueType)) {}
    fn is_header(&self) -> bool {
        matches!(self, Block::Start)
    }
    fn connector(&self) -> Connector {
        match self {
            Block::Label | Block::Button(_) => Connector::Part,
            _ => Connector::Normal,
        }
    }
    fn body_connector(&self, _slot: u8) -> Connector {
        match self {
            Block::Window(_) => Connector::Part,
            _ => Connector::Normal,
        }
    }
    fn body(&self, slot: u8) -> Option<&Vec<Instruction<Block>>> {
        match (self, slot) {
            (Block::Window(body) | Block::Button(body), 0) => Some(body),
            _ => None,
        }
    }
    fn body_mut(&mut self, slot: u8) -> Option<&mut Vec<Instruction<Block>>> {
        match (self, slot) {
            (Block::Window(body) | Block::Button(body), 0) => Some(body),
            _ => None,
        }
    }
}

fn ins(kind: Block) -> Instruction<Block> {
    Instruction::new(kind)
}

/// `Start; Window { Label; Button { Say } }`, plus a loose `Say` and a loose `Label`.
fn graph() -> (BlockGraph<Block>, String, String, String) {
    let mut g = BlockGraph::new();
    let main = g.add_strand(
        0,
        0,
        vec![
            ins(Block::Start),
            ins(Block::Window(vec![
                ins(Block::Label),
                ins(Block::Button(vec![ins(Block::Say)])),
            ])),
        ],
    );
    let say = g.add_strand(400, 0, vec![ins(Block::Say)]);
    let label = g.add_strand(400, 200, vec![ins(Block::Label)]);
    (g, main, say, label)
}

fn in_window(index: usize) -> Vec<PathStep> {
    vec![PathStep::into_body(1, 0), PathStep::at(index)]
}

#[test]
fn parts_go_in_the_window_and_normal_blocks_go_in_the_button() {
    let (mut g, main, _, _) = graph();
    assert!(
        g.insert_instruction(&main, &in_window(0), ins(Block::Label))
            .unwrap()
    );
    let in_button = vec![
        PathStep::into_body(1, 0),
        PathStep::into_body(2, 0),
        PathStep::at(1),
    ];
    assert!(
        g.insert_instruction(&main, &in_button, ins(Block::Say))
            .unwrap()
    );
}

#[test]
fn a_normal_block_is_refused_inside_the_window() {
    let (mut g, main, say, _) = graph();
    let err = g
        .insert_instruction(&main, &in_window(1), ins(Block::Say))
        .unwrap_err();
    assert_eq!(err, "Only window parts fit here");
    assert!(g.merge_strand(&say, &main, &in_window(0)).is_err());
    assert!(
        g.merge_tail(&say, &[PathStep::at(0)], &main, &in_window(0))
            .is_err()
    );
    assert_eq!(
        g.strand(&main).unwrap().instructions[1]
            .body(0)
            .unwrap()
            .len(),
        2
    );
}

#[test]
fn a_part_is_refused_in_a_normal_stack() {
    let (mut g, main, say, label) = graph();
    let err = g
        .insert_instruction(&main, &[PathStep::at(2)], ins(Block::Label))
        .unwrap_err();
    assert_eq!(
        err,
        "A window part only fits inside the block it belongs to"
    );
    assert!(g.merge_strand(&label, &say, &[PathStep::at(1)]).is_err());
    // Out of the window and under the window block.
    assert!(
        g.merge_tail(&main, &in_window(0), &main, &[PathStep::at(2)])
            .is_err()
    );
    let in_button = vec![
        PathStep::into_body(1, 0),
        PathStep::into_body(1, 0),
        PathStep::at(0),
    ];
    assert!(
        g.insert_instruction(&main, &in_button, ins(Block::Label))
            .is_err()
    );
}

#[test]
fn loose_parts_stack_together_and_drop_back_in() {
    let (mut g, main, _, label) = graph();
    assert!(
        g.insert_instruction(&label, &[PathStep::at(1)], ins(Block::Label))
            .unwrap()
    );
    g.merge_strand(&label, &main, &in_window(2)).unwrap();
    assert_eq!(
        g.strand(&main).unwrap().instructions[1]
            .body(0)
            .unwrap()
            .len(),
        4
    );
    // A part dragged out onto the canvas as its own strand.
    g.split_strand(&main, &in_window(3), 500, 500).unwrap();
    g.merge_tail(&main, &in_window(0), &main, &in_window(0))
        .unwrap();
}

#[test]
fn a_paste_must_not_mix_parts_and_normal_blocks() {
    let (g, ..) = graph();
    let mixed = Fragment {
        instructions: vec![ins(Block::Say), ins(Block::Label)],
        comments: vec![],
    };
    assert!(g.check_paste(&mixed).is_err());
    let wrong_inside = Fragment {
        instructions: vec![ins(Block::Window(vec![ins(Block::Say)]))],
        comments: vec![],
    };
    assert!(g.check_paste(&wrong_inside).is_err());
    let parts = Fragment {
        instructions: vec![ins(Block::Label), ins(Block::Button(vec![ins(Block::Say)]))],
        comments: vec![],
    };
    assert!(g.check_paste(&parts).is_ok());
}
