//! Fragments and the frontend codec: clones get fresh ids through every
//! declared body (a dynamic number of branches included), notes follow
//! their clones, pastes refuse what can't land, and the flat frontend shape
//! touches instructions only.

use blockstitch_core::editor::{Created, EditCommand, EditContext, EditError, History, PathStep};
use blockstitch_core::graph::{
    BlockDef, BlockGraph, BlockKind, BlockShape, Comment, Fragment, InputValueType, Instruction,
    from_frontend, to_frontend,
};
use blockstitch_core::value::Value;
use serde::{Deserialize, Serialize};
use serde_json::json;
use std::collections::HashSet;

#[derive(Debug, Clone, PartialEq, Hash, Serialize, Deserialize)]
#[serde(tag = "type")]
enum Block {
    Start,
    Define {
        block_id: String,
    },
    Say {
        text: Value,
    },
    Try {
        body: Vec<Instruction<Block>>,
        catch_body: Vec<Instruction<Block>>,
    },
    /// A custom block call with any number of branch bodies.
    Call {
        block_id: String,
        branches: Vec<Vec<Instruction<Block>>>,
    },
    /// Host data the editor never looks inside.
    Plugin {
        payload: serde_json::Value,
    },
}

impl BlockKind for Block {
    const BODY_SLOTS: u8 = u8::MAX;

    fn visit_values_mut(&mut self, f: &mut dyn FnMut(&mut Value, InputValueType)) {
        if let Block::Say { text } = self {
            f(text, InputValueType::Any);
        }
    }
    fn is_header(&self) -> bool {
        matches!(self, Block::Start | Block::Define { .. })
    }
    fn block_header_id(&self) -> Option<&str> {
        match self {
            Block::Define { block_id } => Some(block_id),
            _ => None,
        }
    }
    fn called_block(&self) -> Option<&str> {
        match self {
            Block::Call { block_id, .. } => Some(block_id),
            _ => None,
        }
    }
    fn calls_block(&self, id: &str) -> bool {
        self.called_block() == Some(id)
    }
    fn body(&self, slot: u8) -> Option<&Vec<Instruction<Block>>> {
        match (self, slot) {
            (Block::Try { body, .. }, 0) => Some(body),
            (Block::Try { catch_body, .. }, 1) => Some(catch_body),
            (Block::Call { branches, .. }, slot) => branches.get(slot as usize),
            _ => None,
        }
    }
    fn body_mut(&mut self, slot: u8) -> Option<&mut Vec<Instruction<Block>>> {
        match (self, slot) {
            (Block::Try { body, .. }, 0) => Some(body),
            (Block::Try { catch_body, .. }, 1) => Some(catch_body),
            (Block::Call { branches, .. }, slot) => branches.get_mut(slot as usize),
            _ => None,
        }
    }
}

fn say(text: &str) -> Instruction<Block> {
    Instruction::new(Block::Say {
        text: Value::text(text),
    })
}

fn ids(instructions: &[Instruction<Block>]) -> Vec<String> {
    let mut out = Vec::new();
    for root in instructions {
        root.walk(&mut |ins| out.push(ins.id.clone()));
    }
    out
}

const BLOCK: &str = "blk";

/// `Start`, then a call with three branches (one holding a try), then a say.
fn graph() -> BlockGraph<Block> {
    let mut graph = BlockGraph::new();
    graph.block_defs.push(BlockDef {
        id: BLOCK.into(),
        pieces: Vec::new(),
        shape: BlockShape::Normal,
        color: "#888888".into(),
        icon: String::new(),
        identifier: String::new(),
        description: String::new(),
    });
    let try_block = Instruction::new(Block::Try {
        body: vec![say("try")],
        catch_body: vec![say("caught")],
    });
    let call = Instruction::new(Block::Call {
        block_id: BLOCK.into(),
        branches: vec![vec![say("a")], vec![], vec![try_block]],
    });
    graph.add_strand(
        0,
        0,
        vec![Instruction::new(Block::Start), call, say("after")],
    );
    graph
}

fn strand(graph: &BlockGraph<Block>) -> String {
    graph.strands[0].id.clone()
}

fn pin(graph: &mut BlockGraph<Block>, to: &str, text: &str) {
    graph
        .comments
        .push(Comment::new(5, 6, text.into(), Some(to.into())));
}

fn ctx() -> EditContext {
    EditContext::default()
}

#[test]
fn a_clone_renames_every_body_including_dynamic_branches() {
    let graph = graph();
    let original = graph.strands[0].instructions[1].clone();
    let mut map = Default::default();
    let copy = original.clone_fresh(&mut map);
    let before = ids(std::slice::from_ref(&original));
    let after = ids(std::slice::from_ref(&copy));
    // call, a, try, try's body, catch body
    assert_eq!(before.len(), 5);
    assert_eq!(after.len(), 5);
    assert!(after.iter().all(|id| !before.contains(id)));
    assert_eq!(after.iter().collect::<HashSet<_>>().len(), 5);
    assert_eq!(map.len(), 5);
    for (old, new) in before.iter().zip(&after) {
        assert_eq!(&map[old], new);
    }
    assert_eq!(copy, original, "kinds are unchanged");
}

#[test]
fn copy_carries_notes_on_nested_blocks_and_paste_repins_them() {
    let mut graph = graph();
    let caught_id = {
        let Block::Call { branches, .. } = &graph.strands[0].instructions[1].kind else {
            panic!()
        };
        let Block::Try { catch_body, .. } = &branches[2][0].kind else {
            panic!()
        };
        catch_body[0].id.clone()
    };
    pin(&mut graph, &caught_id, "inner");
    let start_id = graph.strands[0].instructions[0].id.clone();
    pin(&mut graph, &start_id, "outside");
    graph.comments.push(Comment::new(0, 0, "free".into(), None));

    let fragment = graph
        .copy_fragment(&strand(&graph), &[PathStep::at(1)], None)
        .unwrap();
    assert_eq!(fragment.instructions.len(), 2, "the call and the say after");
    assert_eq!(fragment.comments.len(), 1);
    assert_eq!(fragment.comments[0].text, "inner");

    let outcome = graph
        .apply_edit(
            EditCommand::PasteFragment {
                fragment: fragment.clone(),
                x: 40,
                y: 50,
            },
            &ctx(),
        )
        .unwrap();
    assert!(outcome.changed);
    let pasted = graph.strands.last().unwrap();
    assert_eq!((pasted.x, pasted.y), (40, 50));
    assert_eq!(outcome.created[0], Created::Strand(pasted.id.clone()));
    let pasted_ids = ids(&pasted.instructions);
    assert_eq!(pasted_ids.len(), 6);
    let all = graph.instruction_ids();
    assert_eq!(all.len(), 7 + 6, "every id on the canvas is unique");

    let new_note = graph.comments.last().unwrap();
    assert_eq!(new_note.text, "inner");
    assert_eq!(
        new_note.attached_to.as_ref(),
        Some(&outcome.ids[&caught_id])
    );
    assert!(pasted_ids.contains(&outcome.ids[&caught_id]));
    assert_eq!((new_note.x, new_note.y), (5, 6));
    assert_eq!(outcome.created[1], Created::Comment(new_note.id.clone()));
    assert_eq!(graph.comments.len(), 4);
}

#[test]
fn pasting_one_copy_twice_gives_two_sets_of_ids() {
    let mut graph = graph();
    let fragment = graph
        .copy_fragment(&strand(&graph), &[PathStep::at(1)], Some(1))
        .unwrap();
    for _ in 0..2 {
        graph
            .apply_edit(
                EditCommand::PasteFragment {
                    fragment: fragment.clone(),
                    x: 0,
                    y: 0,
                },
                &ctx(),
            )
            .unwrap();
    }
    let mut seen = HashSet::new();
    graph.walk_instructions(&mut |ins| assert!(seen.insert(ins.id.clone())));
    assert_eq!(seen.len(), 7 + 5 + 5);
}

#[test]
fn duplicate_inserts_after_with_fresh_ids_and_notes() {
    let mut graph = graph();
    let say_id = graph.strands[0].instructions[2].id.clone();
    pin(&mut graph, &say_id, "note");
    let mut history = History::new(10);
    let prepared = graph
        .prepare_edit(
            EditCommand::DuplicateInstruction {
                strand_id: strand(&graph),
                path: vec![PathStep::at(2)],
            },
            &ctx(),
        )
        .unwrap();
    assert!(prepared.changes());
    history.checkpoint(graph.clone(), prepared.coalesce().cloned());
    let outcome = graph.commit_edit(prepared);
    let list = &graph.strands[0].instructions;
    assert_eq!(list.len(), 4);
    assert_eq!(list[3].kind, list[2].kind);
    assert_eq!(outcome.ids[&say_id], list[3].id);
    assert_eq!(graph.comments.len(), 2);
    assert_eq!(graph.comments[1].attached_to.as_ref(), Some(&list[3].id));

    // Nested: the try inside the call's third branch.
    let nested = vec![PathStep::into_body(1, 2), PathStep::at(0)];
    graph
        .apply_edit(
            EditCommand::DuplicateInstruction {
                strand_id: strand(&graph),
                path: nested,
            },
            &ctx(),
        )
        .unwrap();
    let Block::Call { branches, .. } = &graph.strands[0].instructions[1].kind else {
        panic!()
    };
    assert_eq!(branches[2].len(), 2);
    assert_eq!(branches[2][0].kind, branches[2][1].kind);
    let mut seen = HashSet::new();
    graph.walk_instructions(&mut |ins| assert!(seen.insert(ins.id.clone())));

    // One step back undoes the first duplicate whole.
    let before = history.undo(graph.clone()).unwrap();
    assert_eq!(before.strands[0].instructions.len(), 3);
    assert_eq!(before.comments.len(), 1);
}

#[test]
fn refused_pastes_and_duplicates_leave_the_graph_alone() {
    let mut graph = graph();
    let pristine = graph.clone();
    let id = strand(&graph);
    let rejected = |graph: &mut BlockGraph<Block>, command| match graph.apply_edit(command, &ctx())
    {
        Err(EditError::Rejected(why)) => why,
        other => panic!("expected a rejection, got {other:?}"),
    };

    // A header can't be duplicated below itself.
    let why = rejected(
        &mut graph,
        EditCommand::DuplicateInstruction {
            strand_id: id.clone(),
            path: vec![PathStep::at(0)],
        },
    );
    assert!(why.contains("first block"), "{why}");

    // A header anywhere but first.
    let why = rejected(
        &mut graph,
        EditCommand::PasteFragment {
            fragment: Fragment::new(vec![say("x"), Instruction::new(Block::Start)]),
            x: 0,
            y: 0,
        },
    );
    assert!(why.contains("first block"), "{why}");

    // A custom block's definition.
    let why = rejected(
        &mut graph,
        EditCommand::PasteFragment {
            fragment: Fragment::new(vec![Instruction::new(Block::Define {
                block_id: BLOCK.into(),
            })]),
            x: 0,
            y: 0,
        },
    );
    assert!(why.contains("definition"), "{why}");

    // Nothing at all.
    rejected(
        &mut graph,
        EditCommand::PasteFragment {
            fragment: Fragment::new(Vec::new()),
            x: 0,
            y: 0,
        },
    );
    assert_eq!(graph, pristine);
    assert_eq!(graph.instruction_ids(), pristine.instruction_ids());

    // A missing path.
    assert!(matches!(
        graph.apply_edit(
            EditCommand::DuplicateInstruction {
                strand_id: id,
                path: vec![PathStep::at(9)],
            },
            &ctx(),
        ),
        Err(EditError::Missing(_))
    ));
}

#[test]
fn a_paste_into_a_canvas_without_the_called_blocks_is_refused() {
    let graph = graph();
    let fragment = graph
        .copy_fragment(&strand(&graph), &[PathStep::at(1)], None)
        .unwrap();
    assert_eq!(
        fragment.called_blocks().into_iter().collect::<Vec<_>>(),
        [BLOCK]
    );
    let mut other: BlockGraph<Block> = BlockGraph::new();
    let err = other
        .apply_edit(
            EditCommand::PasteFragment {
                fragment,
                x: 0,
                y: 0,
            },
            &ctx(),
        )
        .unwrap_err();
    assert!(err.to_string().contains(BLOCK), "{err}");
    assert!(other.strands.is_empty());

    // A reporter call counts too, and plain blocks paste fine.
    let reporter = Instruction::new(Block::Say {
        text: Value::Call {
            block_id: "gone".into(),
            args: Vec::new(),
            branches: Vec::new(),
            saved: Box::new(Value::number(0.0)),
        },
    });
    let paste = |fragment| EditCommand::PasteFragment {
        fragment,
        x: 0,
        y: 0,
    };
    assert!(
        other
            .apply_edit(paste(Fragment::new(vec![reporter])), &ctx())
            .is_err()
    );
    assert!(
        other
            .apply_edit(paste(Fragment::new(vec![say("ok")])), &ctx())
            .unwrap()
            .changed
    );
}

#[test]
fn the_frontend_shape_is_flat_and_round_trips() {
    let graph = graph();
    let call = &graph.strands[0].instructions[1];
    let json = to_frontend(call).unwrap();
    assert_eq!(json["id"], call.id.as_str());
    assert_eq!(json["type"], "Call");
    assert!(json.get("kind").is_none());
    let inner = &json["branches"][2][0];
    assert_eq!(inner["type"], "Try");
    assert_eq!(inner["catch_body"][0]["type"], "Say");
    assert_eq!(inner["catch_body"][0]["text"]["kind"], "Text");

    let back: Instruction<Block> = from_frontend(json).unwrap();
    assert_eq!(back.kind, call.kind);
    assert_eq!(ids(&[back]), ids(std::slice::from_ref(call)));

    let whole: BlockGraph<Block> = from_frontend(to_frontend(&graph).unwrap()).unwrap();
    assert_eq!(whole, graph);
    assert_eq!(whole.instruction_ids(), graph.instruction_ids());
}

#[test]
fn host_json_with_id_kind_and_type_keys_passes_through_unchanged() {
    let payload = json!({
        "id": "p1",
        "type": "looks-like-a-block",
        "kind": {"id": "k", "type": "also"},
        "items": [{"id": "x", "kind": {"a": 1}}, {"id": "y", "type": "z"}],
    });
    let ins = Instruction::new(Block::Plugin {
        payload: payload.clone(),
    });
    let flat = to_frontend(&ins).unwrap();
    assert_eq!(flat["payload"], payload);
    let back: Instruction<Block> = from_frontend(flat).unwrap();
    assert_eq!(
        back.kind,
        Block::Plugin {
            payload: payload.clone()
        }
    );

    // Plain host JSON outside any instruction is not touched either way.
    assert_eq!(to_frontend(&payload).unwrap(), payload);
    assert_eq!(
        from_frontend::<serde_json::Value>(payload.clone()).unwrap(),
        payload
    );
}

#[test]
fn the_stored_shape_does_not_change() {
    let ins = Instruction {
        id: "i1".to_string(),
        kind: Block::Try {
            body: vec![Instruction {
                id: "i2".to_string(),
                kind: Block::Start,
            }],
            catch_body: Vec::new(),
        },
    };
    let stored = serde_json::to_value(&ins).unwrap();
    assert_eq!(
        stored,
        json!({"id": "i1", "kind": {"type": "Try", "body": [{"id": "i2", "kind": {"type": "Start"}}], "catch_body": []}})
    );
    // Saves from before ids existed still load, with a fresh id.
    let legacy: Instruction<Block> = serde_json::from_value(json!({"type": "Start"})).unwrap();
    assert_eq!(legacy.kind, Block::Start);
    assert!(!legacy.id.is_empty());
}

#[test]
fn the_frontend_reader_accepts_stored_and_id_less_instructions() {
    let stored = json!({"id": "s1", "kind": {"type": "Try", "body": [{"id": "s2", "kind": {"type": "Start"}}], "catch_body": []}});
    let ins: Instruction<Block> = from_frontend(stored).unwrap();
    assert_eq!(ids(&[ins]), ["s1", "s2"]);
    let fresh: Instruction<Block> = from_frontend(json!({"type": "Start"})).unwrap();
    assert_eq!(fresh.kind, Block::Start);
    assert!(!fresh.id.is_empty());
    assert!(from_frontend::<Instruction<Block>>(json!({"id": 3, "type": "Start"})).is_err());
}

#[test]
fn a_fragment_travels_in_the_frontend_shape() {
    let mut graph = graph();
    let say_id = graph.strands[0].instructions[2].id.clone();
    pin(&mut graph, &say_id, "n");
    let fragment = graph
        .copy_fragment(&strand(&graph), &[PathStep::at(2)], Some(1))
        .unwrap();
    let json = to_frontend(&fragment).unwrap();
    assert_eq!(json["instructions"][0]["type"], "Say");
    assert_eq!(json["comments"][0]["attached_to"], say_id.as_str());
    let back: Fragment<Block> = from_frontend(json).unwrap();
    assert_eq!(back, fragment);
}

#[derive(Debug, Clone, PartialEq, Hash, Serialize, Deserialize)]
enum Untagged {
    Start,
}

impl BlockKind for Untagged {
    fn visit_values_mut(&mut self, _: &mut dyn FnMut(&mut Value, InputValueType)) {}
}

#[test]
fn a_kind_that_is_not_an_object_cannot_be_flattened() {
    let err = to_frontend(&Instruction::new(Untagged::Start)).unwrap_err();
    assert!(err.to_string().contains("object"), "{err}");
}
