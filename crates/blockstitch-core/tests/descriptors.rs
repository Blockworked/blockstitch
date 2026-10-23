//! Operator descriptors against the constructors and evaluator they describe,
//! and the generated table BlockRegistry.qml carries.

use blockstitch_core::editor::apply_value_kind;
use blockstitch_core::graph::{
    DictEntry, DictItem, ListItem, dict_reporter_name_index, list_reporter_name_index,
    resolve_dict_reporter, resolve_list_reporter,
};
use blockstitch_core::value::{
    BUILTIN_OPERATOR_KINDS, Evaluated, ExtOperator, NameSource, OperatorDescriptor, ValueType,
    builtin_operator_descriptors, host_operator_descriptors, operator_descriptor,
    operator_descriptors, register_operators, render_descriptors_qml, replace_generated,
};
use blockstitch_core::{Op, Value};
use std::collections::HashMap;

fn type_of(e: &Evaluated) -> ValueType {
    match e {
        Evaluated::Number(_) => ValueType::Number,
        Evaluated::Text(_) => ValueType::Text,
        Evaluated::Bool(_) => ValueType::Bool,
    }
}

#[test]
fn fresh_values_equal_the_native_constructors() {
    for spec in BUILTIN_OPERATOR_KINDS {
        let d = operator_descriptor(spec.kind).unwrap();
        let native = Value::op(Op::from_name(spec.op), (spec.default_args)());
        assert_eq!(d.fresh_value(), native, "{}", spec.kind);
        assert_eq!(d.arity, spec.arity, "{}", spec.kind);
        assert_eq!(d.args.len(), spec.arity, "{}", spec.kind);
        // What apply_value_kind makes of a fresh leaf, minus the leaf it tucks away.
        let mut swapped = Value::number(0.0);
        apply_value_kind(&mut swapped, spec.kind, &HashMap::new()).unwrap();
        assert_eq!(swapped, native, "{}", spec.kind);
    }
}

#[test]
fn wire_names_survive_a_save() {
    for d in builtin_operator_descriptors() {
        let value = d.fresh_value();
        let json = serde_json::to_string(&value).unwrap();
        assert!(json.contains(&format!("\"op\":\"{}\"", d.op)), "{json}");
        let back: Value = serde_json::from_str(&json).unwrap();
        assert_eq!(back, value);
    }
}

#[test]
fn result_and_slot_types_match_what_the_evaluator_does() {
    let lists = HashMap::from([("items".to_string(), vec![ListItem::Text("thing".into())])]);
    let dicts = HashMap::from([(
        "d".to_string(),
        vec![DictEntry::new("key".into(), DictItem::Text("v".into()))],
    )]);
    for d in builtin_operator_descriptors() {
        let mut value = d.fresh_value();
        let Value::Op { args, .. } = &mut value else {
            unreachable!()
        };
        for (arg, descriptor) in args.iter_mut().zip(&d.args) {
            match descriptor.names {
                Some(NameSource::List) => *arg = Value::text("items"),
                Some(NameSource::Dict) => *arg = Value::text("d"),
                None => {}
            }
            if descriptor.default != Value::Bool {
                let evaluated = descriptor.default.eval().unwrap();
                assert_eq!(type_of(&evaluated), descriptor.ty, "{} slot", d.kind);
            }
        }
        let Value::Op { args, .. } = value.clone() else {
            unreachable!()
        };
        let result = if list_reporter_name_index(&d.op).is_some() {
            resolve_list_reporter(&d.op, args, &lists).and_then(|v| v.eval())
        } else if dict_reporter_name_index(&d.op).is_some() {
            resolve_dict_reporter(&d.op, args, &dicts).and_then(|v| v.eval())
        } else {
            value.eval()
        };
        match result {
            Ok(e) => assert_eq!(Some(type_of(&e)), d.result, "{}", d.kind),
            // 0 / 0, 0 mod 0, letter 1 of "": the defaults needn't evaluate.
            Err(_) => assert!(
                ["Div", "Mod", "LetterOf"].contains(&d.kind.as_str()),
                "{}",
                d.kind
            ),
        }
    }
}

#[test]
fn every_choice_is_a_word_the_evaluator_knows() {
    let mut seen = 0;
    for d in builtin_operator_descriptors() {
        for (i, arg) in d.args.iter().enumerate() {
            for choice in &arg.choices {
                let mut value = d.fresh_value();
                let Value::Op { args, .. } = &mut value else {
                    unreachable!()
                };
                args[i] = Value::text(choice.clone());
                assert!(value.eval().is_ok(), "{} {choice}", d.kind);
                seen += 1;
            }
            if !arg.choices.is_empty() {
                assert!(
                    arg.choices.contains(&arg.default.eval_text().unwrap()),
                    "{}",
                    d.kind
                );
            }
        }
    }
    assert_eq!(seen, 16 + 2 + 7);
}

#[test]
fn collection_name_slots_are_where_the_core_reads_them() {
    for d in builtin_operator_descriptors() {
        let index = list_reporter_name_index(&d.op).or(dict_reporter_name_index(&d.op));
        let named: Vec<usize> = (0..d.args.len())
            .filter(|&i| d.args[i].names.is_some())
            .collect();
        assert_eq!(named, index.into_iter().collect::<Vec<_>>(), "{}", d.kind);
    }
    let item = operator_descriptor("ListItem").unwrap();
    assert!(item.args[0].one_based);
    assert_eq!(item.args[1].names, Some(NameSource::List));
}

fn answer(_: &[Evaluated]) -> Result<Evaluated, String> {
    Ok(Evaluated::Number(42.0))
}

static HOST: &[ExtOperator] = &[
    ExtOperator {
        kind: "DescriptorTestReporter",
        op: "DescriptorTestReporter",
        arity: 2,
        default_args: || {
            vec![
                Value::text("a"),
                Value::op(Op::Add, vec![Value::number(1.0), Value::number(2.0)]),
            ]
        },
        eval: answer,
    },
    // A built-in wins the lookup, so it isn't described twice.
    ExtOperator {
        kind: "Add",
        op: "Add",
        arity: 0,
        default_args: Vec::new,
        eval: answer,
    },
];

#[test]
fn host_operators_are_described_after_the_builtins() {
    register_operators(HOST);
    let hosts = host_operator_descriptors();
    let d = hosts
        .iter()
        .find(|d| d.kind == "DescriptorTestReporter")
        .unwrap();
    assert!(d.host);
    assert_eq!(d.result, None);
    assert_eq!(d.args[0].ty, ValueType::Text);
    assert_eq!(d.args[1].ty, ValueType::Number);
    assert!(hosts.iter().all(|d| d.kind != "Add"));
    let all = operator_descriptors();
    assert_eq!(all.iter().filter(|d| d.kind == "Add").count(), 1);
    assert!(all.iter().position(|d| d.host).unwrap() >= builtin_operator_descriptors().len());
}

#[test]
fn descriptors_round_trip_as_json() {
    let all = builtin_operator_descriptors();
    let json = serde_json::to_string(&all).unwrap();
    let back: Vec<OperatorDescriptor> = serde_json::from_str(&json).unwrap();
    assert_eq!(back, all);
    let math = serde_json::to_value(operator_descriptor("Math").unwrap()).unwrap();
    assert_eq!(math["result"], "number");
    assert_eq!(math["args"][0]["type"], "text");
    assert_eq!(
        math["args"][0]["default"],
        serde_json::json!({"kind": "Text", "value": "Abs"})
    );
}

/// BlockRegistry.qml carries the built-in table so a frontend with no
/// backend (or before one answers) builds the same fresh values.
/// `BLESS=1 cargo test --test descriptors` rewrites it.
#[test]
fn block_registry_carries_the_current_table() {
    let path = concat!(
        env!("CARGO_MANIFEST_DIR"),
        "/../../qml/Blockstitch/BlockRegistry.qml"
    );
    let text = std::fs::read_to_string(path).unwrap();
    let block = format!(
        "    readonly property var builtinDescriptors: {}",
        render_descriptors_qml(&builtin_operator_descriptors(), "    ")
    );
    let begin = "// BEGIN GENERATED operator descriptors";
    let end = "// END GENERATED operator descriptors";
    let next = replace_generated(&text, begin, end, &block).expect("markers in BlockRegistry.qml");
    if std::env::var_os("BLESS").is_some() {
        std::fs::write(path, &next).unwrap();
    } else {
        assert!(
            next == text,
            "BlockRegistry.qml's operator table is stale; rerun with BLESS=1"
        );
    }
}
