use super::*;

#[test]
fn legacy_bare_number_deserializes_to_number() {
    let v: Value = serde_json::from_str("5.0").unwrap();
    assert_eq!(v, Value::number(5.0));
}

#[test]
fn legacy_bare_string_deserializes_to_text() {
    // Pre-`Value` save shape of a text field, from back when it held a
    // plain `String` - must keep loading old documents.
    let v: Value = serde_json::from_str("\"hello\"").unwrap();
    assert_eq!(v, Value::text("hello"));
}

#[test]
fn eval_text_passes_through_text_leaf() {
    assert_eq!(Value::text("hi").eval_text(), Ok("hi".to_string()));
}

#[test]
fn eval_text_stringifies_numeric_result() {
    let v = Value::op(Op::Add, vec![Value::number(2.0), Value::number(3.0)]);
    assert_eq!(v.eval_text(), Ok("5".to_string()));
}

#[test]
fn tagged_shape_round_trips() {
    let v = Value::op(Op::Add, vec![Value::number(2.0), Value::text("3")]);
    let json = serde_json::to_string(&v).unwrap();
    let back: Value = serde_json::from_str(&json).unwrap();
    assert_eq!(v, back);
}

#[test]
fn legacy_binary_op_tag_migrates_to_op() {
    let json = r#"{"kind":"BinaryOp","op":"Add","lhs":{"kind":"Number","value":2.0},"rhs":{"kind":"Number","value":3.0},"saved":{"kind":"Number","value":0.0}}"#;
    let v: Value = serde_json::from_str(json).unwrap();
    assert_eq!(
        v,
        Value::op(Op::Add, vec![Value::number(2.0), Value::number(3.0)])
    );
}

#[test]
fn legacy_join_tag_migrates_to_op() {
    let json = r#"{"kind":"Join","args":[{"kind":"Text","value":"a"},{"kind":"Text","value":"b"}],"saved":{"kind":"Number","value":0.0}}"#;
    let v: Value = serde_json::from_str(json).unwrap();
    assert_eq!(
        v,
        Value::op(Op::Join, vec![Value::text("a"), Value::text("b")])
    );
}

#[test]
fn eval_number_nested_expression() {
    // (2 + 3) * 4 == 20
    let v = Value::op(
        Op::Mul,
        vec![
            Value::op(Op::Add, vec![Value::number(2.0), Value::number(3.0)]),
            Value::number(4.0),
        ],
    );
    assert_eq!(v.eval_number(), Ok(20.0));
}

#[test]
fn eval_number_division_by_zero_errs() {
    let v = Value::op(Op::Div, vec![Value::number(1.0), Value::number(0.0)]);
    assert!(v.eval_number().is_err());
}

#[test]
fn eval_number_random_integer_stays_in_range_when_both_bounds_whole() {
    let v = Value::op(Op::Random, vec![Value::number(1.0), Value::number(3.0)]);
    for _ in 0..100 {
        let n = v.eval_number().unwrap();
        assert_eq!(n.fract(), 0.0);
        assert!((1.0..=3.0).contains(&n));
    }
}

#[test]
fn eval_number_random_float_when_a_bound_has_a_fraction() {
    let v = Value::op(Op::Random, vec![Value::number(1.0), Value::number(2.5)]);
    for _ in 0..100 {
        assert!((1.0..=2.5).contains(&v.eval_number().unwrap()));
    }
}

#[test]
fn eval_number_random_handles_reversed_bounds() {
    let v = Value::op(Op::Random, vec![Value::number(5.0), Value::number(1.0)]);
    for _ in 0..100 {
        assert!((1.0..=5.0).contains(&v.eval_number().unwrap()));
    }
}

#[test]
fn eval_number_coerces_numeric_text() {
    let v = Value::op(Op::Add, vec![Value::text("5"), Value::number(3.0)]);
    assert_eq!(v.eval_number(), Ok(8.0));
}

#[test]
fn eval_number_non_numeric_text_errs() {
    assert!(Value::text("abc").eval_number().is_err());
}

#[test]
fn get_mut_walks_path() {
    let mut v = Value::op(
        Op::Add,
        vec![
            Value::number(1.0),
            Value::op(Op::Mul, vec![Value::number(2.0), Value::number(3.0)]),
        ],
    );
    assert_eq!(v.get_mut(&[1, 0]), Some(&mut Value::number(2.0)));
    assert_eq!(v.get_mut(&[0]), Some(&mut Value::number(1.0)));
    assert_eq!(v.get_mut(&[5]), None);
}

#[test]
fn eval_text_joins_args() {
    let v = Value::op(Op::Join, vec![Value::text("foo"), Value::text("bar")]);
    assert_eq!(v.eval_text(), Ok("foobar".to_string()));
    let v = Value::op(
        Op::Join,
        vec![Value::text("a"), Value::number(2.0), Value::text("c")],
    );
    assert_eq!(v.eval_text(), Ok("a2c".to_string()));
}

#[test]
fn eval_text_new_line_and_tab_are_constants() {
    assert_eq!(Value::op(Op::NewLine, vec![]).eval_text(), Ok("\n".into()));
    assert_eq!(Value::op(Op::Tab, vec![]).eval_text(), Ok("\t".into()));
}

#[test]
fn eval_number_mod_wraps_like_rem_euclid() {
    let v = Value::op(Op::Mod, vec![Value::number(-1.0), Value::number(5.0)]);
    assert_eq!(v.eval_number(), Ok(4.0));
}

#[test]
fn eval_number_mod_by_zero_errs() {
    let v = Value::op(Op::Mod, vec![Value::number(1.0), Value::number(0.0)]);
    assert!(v.eval_number().is_err());
}

#[test]
fn eval_number_round_rounds_half_away_from_zero() {
    let v = Value::op(Op::Round, vec![Value::number(2.5)]);
    assert_eq!(v.eval_number(), Ok(3.0));
}

fn math(function: &str, n: f64) -> Value {
    Value::op(Op::Math, vec![Value::text(function), Value::number(n)])
}

#[test]
fn eval_number_math_functions_match_scratch_conventions() {
    assert_eq!(math("Abs", -3.5).eval_number(), Ok(3.5));
    assert_eq!(math("Floor", 2.9).eval_number(), Ok(2.0));
    assert_eq!(math("Ceiling", 2.1).eval_number(), Ok(3.0));
    assert_eq!(math("Sign", -2.0).eval_number(), Ok(-1.0));
    assert_eq!(math("Sign", 0.0).eval_number(), Ok(0.0));
    assert_eq!(math("Sign", 2.0).eval_number(), Ok(1.0));
    assert_eq!(math("Sqrt", 9.0).eval_number(), Ok(3.0));
    assert!((math("Sin", 90.0).eval_number().unwrap() - 1.0).abs() < 1e-12);
    assert!((math("Cos", 180.0).eval_number().unwrap() + 1.0).abs() < 1e-12);
    assert!((math("Tan", 45.0).eval_number().unwrap() - 1.0).abs() < 1e-12);
    assert!((math("Asin", 1.0).eval_number().unwrap() - 90.0).abs() < 1e-12);
    assert!((math("Acos", 0.0).eval_number().unwrap() - 90.0).abs() < 1e-12);
    assert!((math("Atan", 1.0).eval_number().unwrap() - 45.0).abs() < 1e-12);
    assert!((math("Ln", std::f64::consts::E).eval_number().unwrap() - 1.0).abs() < 1e-12);
    assert_eq!(math("Log", 100.0).eval_number(), Ok(2.0));
    assert_eq!(math("Log2", 8.0).eval_number(), Ok(3.0));
    assert!((math("EPower", 1.0).eval_number().unwrap() - std::f64::consts::E).abs() < 1e-12);
    assert_eq!(math("TenPower", 3.0).eval_number(), Ok(1000.0));
}

#[test]
fn eval_number_math_rejects_unknown_function() {
    assert!(math("Hyperbolic", 1.0).eval_number().is_err());
}

#[test]
fn eval_number_length_counts_chars_not_bytes() {
    let v = Value::op(Op::Length, vec![Value::text("héllo")]);
    assert_eq!(v.eval_number(), Ok(5.0));
}

#[test]
fn eval_number_index_of_is_one_based() {
    let v = Value::op(Op::IndexOf, vec![Value::text("lo"), Value::text("hello")]);
    assert_eq!(v.eval_number(), Ok(4.0));
}

#[test]
fn eval_number_index_of_not_found_is_zero() {
    let v = Value::op(Op::IndexOf, vec![Value::text("xyz"), Value::text("hello")]);
    assert_eq!(v.eval_number(), Ok(0.0));
}

#[test]
fn eval_number_last_index_of_finds_final_occurrence() {
    let v = Value::op(
        Op::LastIndexOf,
        vec![Value::text("l"), Value::text("hello")],
    );
    assert_eq!(v.eval_number(), Ok(4.0));
}

#[test]
fn eval_text_letter_of_is_one_based() {
    let v = Value::op(Op::LetterOf, vec![Value::number(1.0), Value::text("hello")]);
    assert_eq!(v.eval_text(), Ok("h".to_string()));
}

#[test]
fn eval_text_letter_of_out_of_range_errs() {
    for index in [0.0, 6.0] {
        let v = Value::op(
            Op::LetterOf,
            vec![Value::number(index), Value::text("hello")],
        );
        assert!(v.eval_text().is_err());
    }
}

#[test]
fn current_time_components_stay_in_range() {
    let current = |which: &str| {
        Value::op(Op::CurrentTime, vec![Value::text(which)])
            .eval_number()
            .unwrap()
    };
    assert!(current("Year") >= 2020.0);
    assert!((1.0..=12.0).contains(&current("Month")));
    assert!((1.0..=31.0).contains(&current("Date")));
    assert!((1.0..=7.0).contains(&current("DayOfWeek")));
    assert!((0.0..=23.0).contains(&current("Hour")));
    assert!((0.0..=59.0).contains(&current("Minute")));
    assert!((0.0..=59.0).contains(&current("Second")));
}

#[test]
fn current_time_rejects_unknown_component() {
    let v = Value::op(Op::CurrentTime, vec![Value::text("Fortnight")]);
    assert!(v.eval_number().is_err());
}

#[test]
fn eval_text_case_switches_on_its_dropdown_arg() {
    let case = |which: &str| {
        Value::op(Op::Case, vec![Value::text("Hello"), Value::text(which)]).eval_text()
    };
    assert_eq!(case("Upper"), Ok("HELLO".to_string()));
    assert_eq!(case("Lower"), Ok("hello".to_string()));
}

#[test]
fn resolve_vars_replaces_leaf_with_current_value() {
    let env = HashMap::from([
        ("x".to_string(), Evaluated::Number(5.0)),
        ("s".to_string(), Evaluated::Text("hi".to_string())),
    ]);
    assert_eq!(
        Value::Var {
            name: "x".to_string()
        }
        .resolve_vars(&env),
        Value::number(5.0)
    );
    assert_eq!(
        Value::Var {
            name: "s".to_string()
        }
        .resolve_vars(&env),
        Value::text("hi")
    );
}

#[test]
fn resolve_vars_defaults_missing_name_to_zero() {
    let v = Value::Var {
        name: "missing".to_string(),
    };
    assert_eq!(v.resolve_vars(&HashMap::new()), Value::number(0.0));
}

#[test]
fn resolve_vars_recurses_into_op_args_and_saved() {
    let env = HashMap::from([("x".to_string(), Evaluated::Number(2.0))]);
    let v = Value::Op {
        op: Op::Add,
        args: vec![
            Value::Var {
                name: "x".to_string(),
            },
            Value::number(3.0),
        ],
        saved: Box::new(Value::Var {
            name: "x".to_string(),
        }),
    };
    let resolved = v.resolve_vars(&env);
    assert_eq!(resolved.eval_number(), Ok(5.0));
    match resolved {
        Value::Op { saved, .. } => assert_eq!(*saved, Value::number(2.0)),
        _ => panic!("expected Op"),
    }
}

#[test]
fn eval_errs_on_unresolved_var() {
    assert!(
        Value::Var {
            name: "x".to_string()
        }
        .eval()
        .is_err()
    );
}

#[test]
fn rename_var_renames_matching_leaves_only() {
    let mut v = Value::Op {
        op: Op::Add,
        args: vec![
            Value::Var {
                name: "x".to_string(),
            },
            Value::Var {
                name: "z".to_string(),
            },
        ],
        saved: Box::new(Value::Var {
            name: "x".to_string(),
        }),
    };
    v.rename_var("x", "y");
    match v {
        Value::Op { args, saved, .. } => {
            assert_eq!(
                args[0],
                Value::Var {
                    name: "y".to_string()
                }
            );
            assert_eq!(
                args[1],
                Value::Var {
                    name: "z".to_string()
                }
            );
            assert_eq!(
                *saved,
                Value::Var {
                    name: "y".to_string()
                }
            );
        }
        _ => panic!("expected Op"),
    }
}

#[test]
fn eval_boolean_operators() {
    let t = || Value::op(Op::True, vec![]);
    let f = || Value::op(Op::False, vec![]);
    assert_eq!(t().eval(), Ok(Evaluated::Bool(true)));
    assert_eq!(f().eval(), Ok(Evaluated::Bool(false)));
    assert_eq!(
        Value::op(Op::Not, vec![t()]).eval(),
        Ok(Evaluated::Bool(false))
    );
    assert_eq!(
        Value::op(Op::And, vec![t(), f()]).eval(),
        Ok(Evaluated::Bool(false))
    );
    assert_eq!(
        Value::op(Op::Or, vec![f(), t()]).eval(),
        Ok(Evaluated::Bool(true))
    );
    // A nonzero number is truthy, so `not 5` is false.
    assert_eq!(
        Value::op(Op::Not, vec![Value::number(5.0)]).eval(),
        Ok(Evaluated::Bool(false))
    );
}

#[test]
fn eval_comparisons_are_numeric() {
    let cmp =
        |op: Op, l: f64, r: f64| Value::op(op, vec![Value::number(l), Value::number(r)]).eval();
    assert_eq!(cmp(Op::Gt, 5.0, 3.0), Ok(Evaluated::Bool(true)));
    assert_eq!(cmp(Op::Lt, 5.0, 3.0), Ok(Evaluated::Bool(false)));
    assert_eq!(cmp(Op::Gte, 3.0, 3.0), Ok(Evaluated::Bool(true)));
    assert_eq!(cmp(Op::Lte, 3.0, 3.0), Ok(Evaluated::Bool(true)));
}

#[test]
fn eval_eq_compares_numerically_when_both_sides_are_numeric() {
    let v = Value::op(Op::Eq, vec![Value::text("5"), Value::number(5.0)]);
    assert_eq!(v.eval(), Ok(Evaluated::Bool(true)));
    let v = Value::op(Op::Neq, vec![Value::text("5"), Value::number(5.0)]);
    assert_eq!(v.eval(), Ok(Evaluated::Bool(false)));
}

#[test]
fn eval_eq_falls_back_to_text_comparison_for_non_numeric_text() {
    let eq = |l: Value, r: Value| Value::op(Op::Eq, vec![l, r]).eval();
    assert_eq!(
        eq(Value::text("hello"), Value::text("hello")),
        Ok(Evaluated::Bool(true))
    );
    assert_eq!(
        eq(Value::text("hello"), Value::text("world")),
        Ok(Evaluated::Bool(false))
    );
    assert_eq!(
        eq(Value::text("hello"), Value::number(5.0)),
        Ok(Evaluated::Bool(false))
    );
}

#[test]
fn as_bool_coerces_loosely() {
    assert!(Evaluated::Number(1.0).as_bool());
    assert!(!Evaluated::Number(0.0).as_bool());
    assert!(Evaluated::Text("hi".to_string()).as_bool());
    assert!(!Evaluated::Text(String::new()).as_bool());
    assert!(!Evaluated::Text("false".to_string()).as_bool());
}

#[test]
fn into_value_rebuilds_bool_as_true_false_op() {
    assert_eq!(
        Evaluated::Bool(true).into_value().eval(),
        Ok(Evaluated::Bool(true))
    );
    assert_eq!(
        Evaluated::Bool(false).into_value().eval(),
        Ok(Evaluated::Bool(false))
    );
}

static TEST_OPERATORS: &[ExtOperator] = &[ExtOperator {
    kind: "AnswerToEverything",
    op: "AnswerToEverything",
    arity: 0,
    default_args: Vec::new,
    eval: |_| Ok(Evaluated::Number(42.0)),
}];

#[test]
fn registered_ext_operator_evaluates_and_joins_the_palette() {
    register_operators(TEST_OPERATORS);
    let v = Value::op(Op::from_name("AnswerToEverything"), vec![]);
    assert_eq!(v.eval_number(), Ok(42.0));
    assert_eq!(operator_kind("AnswerToEverything").unwrap().arity, 0);
}

#[test]
fn unregistered_ext_operator_round_trips_but_errs_on_eval() {
    let json = r#"{"kind":"Op","op":"NeverRegistered","args":[],"saved":{"kind":"Number","value":0.0}}"#;
    let v: Value = serde_json::from_str(json).unwrap();
    assert_eq!(serde_json::to_string(&v).unwrap(), json);
    assert!(v.eval().is_err());
}
