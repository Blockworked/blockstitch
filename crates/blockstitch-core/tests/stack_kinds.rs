//! Stack kinds: a body only takes blocks of the kind it holds.

use blockstitch_core::editor::PathStep;
use blockstitch_core::graph::{BlockGraph, BlockKind, InputValueType, Instruction};
use blockstitch_core::value::Value;
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, PartialEq, Hash, Serialize, Deserialize)]
enum Block {
    Say,
    Field,
    Window { body: Vec<Instruction<Block>> },
    Button { body: Vec<Instruction<Block>> },
}

impl BlockKind for Block {
    fn visit_values_mut(&mut self, _f: &mut dyn FnMut(&mut Value, InputValueType)) {}
    fn body(&self, slot: u8) -> Option<&Vec<Instruction<Block>>> {
        match (self, slot) {
            (Block::Window { body } | Block::Button { body }, 0) => Some(body),
            _ => None,
        }
    }
    fn body_mut(&mut self, slot: u8) -> Option<&mut Vec<Instruction<Block>>> {
        match (self, slot) {
            (Block::Window { body } | Block::Button { body }, 0) => Some(body),
            _ => None,
        }
    }
    fn stack_kind(&self) -> &'static str {
        match self {
            Block::Field | Block::Button { .. } => "control",
            _ => "",
        }
    }
    fn body_stack_kind(&self, _slot: u8) -> &'static str {
        match self {
            Block::Window { .. } => "control",
            _ => "",
        }
    }
    fn stack_mismatch(block: &str, _list: &str) -> String {
        format!("mismatch:{block}")
    }
}

fn ins(kind: Block) -> Instruction<Block> {
    Instruction::new(kind)
}

fn window() -> (BlockGraph<Block>, String) {
    let mut g = BlockGraph::new();
    let id = g.add_strand(
        0,
        0,
        vec![
            ins(Block::Say),
            ins(Block::Window {
                body: vec![ins(Block::Field), ins(Block::Button { body: vec![] })],
            }),
        ],
    );
    (g, id)
}

fn in_window(index: usize) -> Vec<PathStep> {
    vec![PathStep::into_body(1, 0), PathStep::at(index)]
}

fn in_button(index: usize) -> Vec<PathStep> {
    vec![
        PathStep::into_body(1, 0),
        PathStep::into_body(1, 0),
        PathStep::at(index),
    ]
}

#[test]
fn insert_matches_the_body_kind() {
    let (mut g, id) = window();
    assert_eq!(
        g.insert_instruction(&id, &in_window(0), ins(Block::Say)),
        Err("mismatch:".to_string())
    );
    assert_eq!(
        g.insert_instruction(&id, &in_button(0), ins(Block::Field)),
        Err("mismatch:control".to_string())
    );
    assert_eq!(
        g.insert_instruction(&id, &in_button(0), ins(Block::Say)),
        Ok(true)
    );
    assert_eq!(
        g.insert_instruction(&id, &in_window(0), ins(Block::Field)),
        Ok(true)
    );
    assert_eq!(
        g.insert_instruction(&id, &[PathStep::at(2)], ins(Block::Field)),
        Err("mismatch:control".to_string())
    );
}

#[test]
fn merges_check_every_dragged_block() {
    let (mut g, id) = window();
    let loose = g.add_strand(400, 0, vec![ins(Block::Field), ins(Block::Say)]);
    let before = g.clone();
    assert!(g.merge_strand(&loose, &id, &in_window(0)).is_err());
    assert_eq!(g.strands.len(), before.strands.len());
    assert!(
        g.merge_tail(&loose, &[PathStep::at(0)], &id, &in_window(0))
            .is_err()
    );
    assert!(
        g.merge_tail(&loose, &[PathStep::at(1)], &id, &in_window(0))
            .is_err()
    );
    assert!(
        g.merge_tail(&loose, &[PathStep::at(1)], &id, &in_button(0))
            .is_ok()
    );
    assert!(g.merge_strand(&loose, &id, &in_window(0)).is_ok());
    let window = &g.strand(&id).unwrap().instructions[1];
    assert_eq!(window.body(0).unwrap().len(), 3);
}

#[test]
fn an_empty_or_loose_strand_takes_any_kind() {
    let (mut g, id) = window();
    let loose = g.add_strand(400, 0, vec![ins(Block::Field)]);
    assert_eq!(
        g.insert_instruction(&loose, &[PathStep::at(1)], ins(Block::Field)),
        Ok(true)
    );
    assert!(
        g.check_stack_kind(&id, &[PathStep::at(0)], &[ins(Block::Say)])
            .is_ok()
    );
}
