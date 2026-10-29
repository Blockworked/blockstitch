//! The typed edit contract: atomic moves, field text policy, delete-tail,
//! no-ops and rejections that leave the graph exactly as it was.

use blockstitch_core::editor::{
    BufferEffect, Created, EditCommand, EditContext, EditError, EditSession, History,
    NumberSpelling, PathStep, ValueBuffers, ValueDestination, ValueLocation, apply_buffer_effects,
};
use blockstitch_core::graph::{BlockDef, BlockGraph, BlockKind, InputValueType, Instruction};
use blockstitch_core::value::{Op, Value};
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, PartialEq, Hash, Serialize, Deserialize)]
enum Block {
    Start,
    Say(Value),
    Wait(Value),
    Repeat {
        count: Value,
        body: Vec<Instruction<Block>>,
    },
}

impl BlockKind for Block {
    fn visit_values_mut(&mut self, f: &mut dyn FnMut(&mut Value, InputValueType)) {
        match self {
            Block::Say(v) | Block::Wait(v) => f(v, InputValueType::Any),
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
            (Block::Say(v), "Say") | (Block::Wait(v), "Wait") => Some(v),
            (Block::Repeat { count, .. }, "Count") => Some(count),
            _ => None,
        }
    }
    fn field_requires_integer(&self, field: &str) -> bool {
        field == "Count"
    }
}

fn add(a: f64, b: f64) -> Value {
    Value::Op {
        op: Op::Add,
        args: vec![Value::number(a), Value::number(b)],
        saved: Box::new(Value::number(7.0)),
    }
}

/// `Start; Say(1 + 2); Wait(5); Repeat(3) { Say("hi") }`
fn graph() -> (BlockGraph<Block>, String) {
    let mut g = BlockGraph::new();
    let id = g.add_strand(
        0,
        0,
        vec![
            Instruction::new(Block::Start),
            Instruction::new(Block::Say(add(1.0, 2.0))),
            Instruction::new(Block::Wait(Value::number(5.0))),
            Instruction::new(Block::Repeat {
                count: Value::number(3.0),
                body: vec![Instruction::new(Block::Say(Value::text("hi")))],
            }),
        ],
    );
    (g, id)
}

fn field(strand: &str, index: usize, field_id: &str, path: Vec<u8>) -> ValueLocation {
    ValueLocation::Field {
        strand_id: strand.to_string(),
        index: vec![PathStep::at(index)],
        field_id: field_id.to_string(),
        path,
    }
}

/// Serialized, so ids count too.
fn snapshot(g: &BlockGraph<Block>) -> serde_json::Value {
    serde_json::to_value(g).unwrap()
}

fn ctx() -> EditContext {
    EditContext::default()
}

fn move_to(from: ValueLocation, to: ValueLocation) -> EditCommand<Block> {
    EditCommand::MoveValue {
        from,
        to: ValueDestination::Slot(to),
    }
}

#[test]
fn moving_a_value_into_a_slot_is_one_step_that_restores_both_sides() {
    let (mut g, s) = graph();
    let mut history = History::new(8);
    let prepared = g
        .prepare_edit(
            move_to(field(&s, 1, "Say", vec![]), field(&s, 2, "Wait", vec![])),
            &ctx(),
        )
        .unwrap();
    assert!(prepared.changes());
    history.checkpoint(g.clone(), prepared.coalesce().cloned());
    let outcome = g.commit_edit(prepared);
    assert!(outcome.changed);

    // The slot it left restores what it shadowed.
    assert_eq!(
        g.value_at(&field(&s, 1, "Say", vec![])),
        Some(Value::number(7.0))
    );
    // The moved operator now shadows what the destination held.
    let moved = g.value_at(&field(&s, 2, "Wait", vec![])).unwrap();
    assert_eq!(moved.saved(), Some(&Value::number(5.0)));
    assert_eq!(
        outcome.buffers,
        vec![
            BufferEffect::Prune(field(&s, 1, "Say", vec![])),
            BufferEffect::Prune(field(&s, 2, "Wait", vec![])),
        ]
    );

    // One gesture, one undo step; redo brings back the same ids and shadows.
    let after = snapshot(&g);
    let before = history.undo(g.clone()).unwrap();
    assert!(!history.can_undo());
    let redone = history.redo(before).unwrap();
    assert_eq!(snapshot(&redone), after);
}

#[test]
fn rejected_and_missing_moves_leave_the_graph_untouched() {
    let (mut g, s) = graph();
    let before = snapshot(&g);
    let cases = [
        // Missing source.
        move_to(field(&s, 9, "Say", vec![]), field(&s, 2, "Wait", vec![])),
        // Missing destination.
        move_to(field(&s, 1, "Say", vec![]), field(&s, 2, "Nope", vec![])),
        // Into its own argument.
        move_to(field(&s, 1, "Say", vec![]), field(&s, 1, "Say", vec![0])),
    ];
    for command in cases {
        assert!(g.apply_edit(command, &ctx()).is_err());
        assert_eq!(snapshot(&g), before);
    }
    assert!(matches!(
        g.apply_edit(
            move_to(field(&s, 1, "Say", vec![]), field(&s, 1, "Say", vec![1])),
            &ctx()
        ),
        Err(EditError::Rejected(_))
    ));
}

#[test]
fn a_move_onto_itself_is_a_valid_no_op() {
    let (mut g, s) = graph();
    let before = snapshot(&g);
    let prepared = g
        .prepare_edit(
            move_to(field(&s, 1, "Say", vec![]), field(&s, 1, "Say", vec![])),
            &ctx(),
        )
        .unwrap();
    assert!(!prepared.changes());
    let outcome = g.commit_edit(prepared);
    assert!(!outcome.changed);
    assert_eq!(snapshot(&g), before);
}

#[test]
fn a_subvalue_moves_up_into_its_own_parent_slot() {
    let (mut g, s) = graph();
    g.apply_edit(
        move_to(field(&s, 1, "Say", vec![1]), field(&s, 1, "Say", vec![])),
        &ctx(),
    )
    .unwrap();
    assert_eq!(
        g.value_at(&field(&s, 1, "Say", vec![])),
        Some(Value::number(2.0))
    );
}

#[test]
fn dropping_on_canvas_parks_a_value_and_keeps_origin_metadata() {
    let (mut g, s) = graph();
    let outcome = g
        .apply_edit(
            EditCommand::MoveValue {
                from: field(&s, 1, "Say", vec![0]),
                to: ValueDestination::Canvas {
                    x: 40,
                    y: 50,
                    origin_block_id: Some("b1".into()),
                },
            },
            &ctx(),
        )
        .unwrap();
    let [Created::FloatingValue(id)] = outcome.created.as_slice() else {
        panic!("expected one floating value, got {:?}", outcome.created);
    };
    let floating = g.floating_value(id).unwrap();
    assert_eq!((floating.x, floating.y), (40, 50));
    assert_eq!(floating.value, Value::number(1.0));
    assert_eq!(floating.origin_block_id.as_deref(), Some("b1"));
    // A nested position restores to a plain zero.
    assert_eq!(
        g.value_at(&field(&s, 1, "Say", vec![0])),
        Some(Value::number(0.0))
    );

    // Moving the parked block again repositions it under the same id and origin.
    let id = id.clone();
    let root = ValueLocation::Floating {
        floating_id: id.clone(),
        path: vec![],
    };
    let again = g
        .apply_edit(
            EditCommand::MoveValue {
                from: root.clone(),
                to: ValueDestination::Canvas {
                    x: 90,
                    y: 10,
                    origin_block_id: None,
                },
            },
            &ctx(),
        )
        .unwrap();
    assert!(again.changed && again.created.is_empty());
    let floating = g.floating_value(&id).unwrap();
    assert_eq!((floating.x, floating.y), (90, 10));
    assert_eq!(floating.origin_block_id.as_deref(), Some("b1"));

    // And into a slot it goes, leaving nothing parked.
    g.apply_edit(move_to(root, field(&s, 2, "Wait", vec![])), &ctx())
        .unwrap();
    assert!(g.floating_values.is_empty());
    assert_eq!(
        g.value_at(&field(&s, 2, "Wait", vec![])),
        Some(Value::number(1.0))
    );
}

#[test]
fn a_parked_block_cannot_drop_into_its_own_argument() {
    let (mut g, _) = graph();
    let id = g.add_floating_value(0, 0, add(1.0, 1.0), None);
    let before = snapshot(&g);
    let result = g.apply_edit(
        move_to(
            ValueLocation::Floating {
                floating_id: id.clone(),
                path: vec![],
            },
            ValueLocation::Floating {
                floating_id: id,
                path: vec![0],
            },
        ),
        &ctx(),
    );
    assert!(matches!(result, Err(EditError::Rejected(_))));
    assert_eq!(snapshot(&g), before);
}

fn type_into(
    g: &mut BlockGraph<Block>,
    loc: &ValueLocation,
    text: &str,
    numbers: NumberSpelling,
) -> blockstitch_core::editor::EditOutcome {
    g.apply_edit(
        EditCommand::EditFieldText {
            location: loc.clone(),
            text: text.into(),
        },
        &EditContext { numbers },
    )
    .unwrap()
}

#[test]
fn numeric_spelling_follows_the_named_policy() {
    let (mut g, s) = graph();
    let operand = field(&s, 1, "Say", vec![0]);

    // Canonical: a number is a number.
    type_into(&mut g, &operand, "09", NumberSpelling::Canonical);
    assert_eq!(g.value_at(&operand), Some(Value::number(9.0)));

    // Keep-typed: an operand keeps "09" / "1.50"; a top-level slot doesn't.
    let (mut g, s) = graph();
    let operand = field(&s, 1, "Say", vec![0]);
    type_into(&mut g, &operand, "09", NumberSpelling::KeepTypedInOperands);
    assert_eq!(g.value_at(&operand), Some(Value::text("09")));
    let other = field(&s, 1, "Say", vec![1]);
    type_into(
        &mut g,
        &other,
        " 1.50 ",
        NumberSpelling::KeepTypedInOperands,
    );
    assert_eq!(g.value_at(&other), Some(Value::text("1.50")));
    let top = field(&s, 2, "Wait", vec![]);
    let outcome = type_into(&mut g, &top, "09", NumberSpelling::KeepTypedInOperands);
    assert_eq!(g.value_at(&top), Some(Value::number(9.0)));
    assert_eq!(
        outcome.buffers,
        vec![BufferEffect::Set {
            location: top.clone(),
            text: "09".into()
        }]
    );
    assert_eq!(outcome.coalesce, Some(EditSession::Value(top)));
}

#[test]
fn partial_numbers_are_buffered_without_touching_the_graph() {
    let (mut g, s) = graph();
    let wait = field(&s, 2, "Wait", vec![]);
    let count = field(&s, 3, "Count", vec![]);
    let before = snapshot(&g);
    let mut buffers = ValueBuffers::new();
    for (loc, text) in [(&wait, "-"), (&wait, "1e"), (&wait, ""), (&count, "1.5")] {
        let outcome = type_into(&mut g, loc, text, NumberSpelling::Canonical);
        assert!(!outcome.changed, "{text:?} is not a number yet");
        apply_buffer_effects(&mut buffers, &outcome.buffers);
        assert_eq!(buffers.get(loc).map(String::as_str), Some(text));
        assert_eq!(snapshot(&g), before);
    }
    // A complete exponent parses.
    assert!(type_into(&mut g, &wait, "1e2", NumberSpelling::Canonical).changed);
    assert_eq!(g.value_at(&wait), Some(Value::number(100.0)));
    // Retyping the same value is a no-op, still buffered.
    let same = type_into(&mut g, &wait, "100", NumberSpelling::Canonical);
    assert!(!same.changed);
    assert_eq!(same.buffers.len(), 1);
}

#[test]
fn text_slots_take_text_verbatim_with_no_buffer() {
    let (mut g, s) = graph();
    let say = ValueLocation::Field {
        strand_id: s.clone(),
        index: vec![PathStep::into_body(3, 0), PathStep::at(0)],
        field_id: "Say".into(),
        path: vec![],
    };
    let outcome = type_into(&mut g, &say, " 09 ", NumberSpelling::Canonical);
    assert!(outcome.changed && outcome.buffers.is_empty());
    assert_eq!(g.value_at(&say), Some(Value::text(" 09 ")));
}

#[test]
fn keystrokes_coalesce_into_one_undo_step_and_no_ops_push_nothing() {
    let (mut g, s) = graph();
    let wait = field(&s, 2, "Wait", vec![]);
    let mut history = History::new(8);
    for text in ["1", "1e", "1e2", "-", "-4"] {
        let prepared = g
            .prepare_edit(
                EditCommand::EditFieldText {
                    location: wait.clone(),
                    text: text.into(),
                },
                &ctx(),
            )
            .unwrap();
        if prepared.changes() {
            history.checkpoint(g.clone(), prepared.coalesce().cloned());
        }
        g.commit_edit(prepared);
    }
    assert_eq!(g.value_at(&wait), Some(Value::number(-4.0)));
    let first = history.undo(g.clone()).unwrap();
    assert_eq!(first.value_at(&wait), Some(Value::number(5.0)));
    assert!(!history.can_undo());
}

#[test]
fn delete_tail_removes_the_run_in_one_step_and_prunes_its_comments() {
    let (mut g, s) = graph();
    let tail_id = g.strand(&s).unwrap().instructions[2].id.clone();
    let kept_id = g.strand(&s).unwrap().instructions[1].id.clone();
    g.add_comment(0, 0, "on the tail".into(), Some(tail_id));
    g.add_comment(0, 0, "on a kept block".into(), Some(kept_id));
    let outcome = g
        .apply_edit(
            EditCommand::RemoveInstructions {
                strand_id: s.clone(),
                path: vec![PathStep::at(2)],
                count: 10,
            },
            &ctx(),
        )
        .unwrap();
    assert!(outcome.changed);
    assert_eq!(outcome.buffers, vec![BufferEffect::DropStrand(s.clone())]);
    assert_eq!(g.strand(&s).unwrap().instructions.len(), 2);
    assert_eq!(g.comments.len(), 1);

    let before = snapshot(&g);
    let missing = g.apply_edit(
        EditCommand::RemoveInstructions {
            strand_id: s.clone(),
            path: vec![PathStep::at(5)],
            count: 1,
        },
        &ctx(),
    );
    assert!(matches!(missing, Err(EditError::Missing(_))));
    assert_eq!(snapshot(&g), before);
}

#[test]
fn delete_tail_inside_a_body() {
    let (mut g, s) = graph();
    g.apply_edit(
        EditCommand::RemoveInstructions {
            strand_id: s.clone(),
            path: vec![PathStep::into_body(3, 0), PathStep::at(0)],
            count: 0,
        },
        &ctx(),
    )
    .unwrap();
    let repeat = &g.strand(&s).unwrap().instructions[3];
    assert!(repeat.body(0).unwrap().is_empty());
}

#[test]
fn insert_checks_header_placement_first() {
    let (mut g, s) = graph();
    let before = snapshot(&g);
    let above_header = g.apply_edit(
        EditCommand::InsertInstruction {
            strand_id: s.clone(),
            path: vec![PathStep::at(0)],
            instruction: Instruction::new(Block::Wait(Value::number(1.0))),
        },
        &ctx(),
    );
    assert!(matches!(above_header, Err(EditError::Rejected(_))));
    assert_eq!(snapshot(&g), before);
    g.apply_edit(
        EditCommand::InsertInstruction {
            strand_id: s.clone(),
            path: vec![PathStep::at(1)],
            instruction: Instruction::new(Block::Wait(Value::number(1.0))),
        },
        &ctx(),
    )
    .unwrap();
    assert_eq!(g.strand(&s).unwrap().instructions.len(), 5);
}

#[test]
fn commands_cross_the_json_boundary() {
    let json = serde_json::json!({
        "move_value": {
            "from": {"kind": "Field", "strand_id": "s1", "index": [{"index": 1, "slot": null}], "field_id": "Say", "path": []},
            "to": {"canvas": {"x": 3, "y": 4}}
        }
    });
    let command: EditCommand<Block> = serde_json::from_value(json.clone()).unwrap();
    assert!(matches!(
        &command,
        EditCommand::MoveValue {
            to: ValueDestination::Canvas {
                x: 3,
                y: 4,
                origin_block_id: None
            },
            ..
        }
    ));
}

#[test]
fn custom_block_details_load_when_absent_and_normalize_when_set() {
    let old: BlockDef = serde_json::from_value(serde_json::json!({
        "id": "b",
        "pieces": [{"kind": "Label", "id": "l1", "text": "jump"}],
        "shape": "Normal"
    }))
    .unwrap();
    assert_eq!(
        (
            old.identifier.as_str(),
            old.description.as_str(),
            old.icon.as_str()
        ),
        ("", "", "")
    );
    let saved = serde_json::to_value(&old).unwrap();
    for key in ["identifier", "description", "icon"] {
        assert_eq!(saved[key], "", "{key} is a shared saved field");
    }

    let mut g: BlockGraph<Block> = BlockGraph::new();
    let id = g.create_block(
        old.pieces.clone(),
        old.shape,
        old.color.clone(),
        0,
        0,
        |_| Block::Start,
    );
    g.set_block_details(&id, "  jump-high ", " Jumps. ", "Not An Icon")
        .unwrap();
    let def = g.block_def(&id).unwrap();
    assert_eq!(def.identifier, "jump-high");
    assert_eq!(def.description, "Jumps.");
    assert_eq!(def.icon, "");
    g.set_block_details(&id, "", "", "arrow-up").unwrap();
    assert_eq!(g.block_def(&id).unwrap().icon, "arrow-up");
    assert!(g.set_block_details("nope", "", "", "").is_err());
}

#[test]
fn empty_boolean_slots_cannot_be_extracted_or_moved() {
    let (mut g, strand) = graph();
    let location = field(&strand, 1, "Say", vec![]);
    assert!(g.put_value(&location, Value::Bool));
    let before = snapshot(&g);
    assert_eq!(g.take_value(&location), None);
    assert!(g
        .prepare_edit(
            move_to(location.clone(), field(&strand, 2, "Wait", vec![])),
            &ctx(),
        )
        .is_err());
    assert_eq!(snapshot(&g), before);

    let reporter = Value::Op {
        op: Op::Not,
        args: vec![Value::Bool],
        saved: Box::new(Value::Bool),
    };
    assert!(g.put_value(&location, reporter.clone()));
    let nested = field(&strand, 1, "Say", vec![0]);
    let before = snapshot(&g);
    assert_eq!(g.take_value(&nested), None);
    assert_eq!(snapshot(&g), before);
    assert_eq!(g.take_value(&location), Some(reporter));
    assert_eq!(g.value_at(&location), Some(Value::Bool));
}
