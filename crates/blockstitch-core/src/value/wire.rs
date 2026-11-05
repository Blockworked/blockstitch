//! How a value hashes and loads: `f64` isn't `Hash`, and older saves spell values differently.

use super::*;

/// Manual impl mirroring the host's own manual `Hash` impls - `f64` isn't
/// `Hash`, so its bit pattern stands in.
impl std::hash::Hash for Value {
    fn hash<H: std::hash::Hasher>(&self, state: &mut H) {
        match self {
            Value::Number { value } => {
                0u8.hash(state);
                value.to_bits().hash(state);
            }
            Value::Text { value } => {
                1u8.hash(state);
                value.hash(state);
            }
            Value::Bool => {
                6u8.hash(state);
            }
            Value::Op { op, args, saved } => {
                2u8.hash(state);
                op.hash(state);
                args.hash(state);
                saved.hash(state);
            }
            Value::Var { name } => {
                3u8.hash(state);
                name.hash(state);
            }
            Value::Param { name } => {
                4u8.hash(state);
                name.hash(state);
            }
            Value::Call {
                block_id,
                args,
                branches,
                saved,
            } => {
                5u8.hash(state);
                block_id.hash(state);
                args.hash(state);
                serde_json::to_string(branches)
                    .unwrap_or_default()
                    .hash(state);
                saved.hash(state);
            }
        }
    }
}

/// Accepts the tagged `{"kind": ...}` shape or a bare number/string, since
/// old save files have plain values in slots `Value` now occupies.
impl<'de> Deserialize<'de> for Value {
    fn deserialize<D>(deserializer: D) -> Result<Self, D::Error>
    where
        D: Deserializer<'de>,
    {
        fn default_saved() -> Box<Value> {
            Box::new(Value::number(0.0))
        }

        #[derive(Deserialize)]
        #[serde(tag = "kind")]
        enum Tagged {
            Number {
                value: f64,
            },
            Text {
                value: String,
            },
            Bool,
            Op {
                op: Op,
                args: Vec<Value>,
                // Older save files predate `saved` entirely - falls back to
                // a plain zero, same spirit as `ValueDe::Legacy` below.
                #[serde(default = "default_saved")]
                saved: Box<Value>,
            },
            Var {
                name: String,
            },
            Param {
                name: String,
            },
            Call {
                block_id: String,
                args: Vec<Value>,
                #[serde(default)]
                branches: Vec<Vec<serde_json::Value>>,
                #[serde(default = "default_saved")]
                saved: Box<Value>,
            },
            // Legacy tags predating the `BinaryOp`/`Join` → `Op` unification -
            // kept so old saves still load, migrated into `Value::Op` below.
            BinaryOp {
                op: Op,
                lhs: Box<Value>,
                rhs: Box<Value>,
                #[serde(default = "default_saved")]
                saved: Box<Value>,
            },
            Join {
                args: Vec<Value>,
                #[serde(default = "default_saved")]
                saved: Box<Value>,
            },
        }

        #[derive(Deserialize)]
        #[serde(untagged)]
        enum ValueDe {
            Legacy(f64),
            // Pre-`Value` shape of a text field - a bare JSON string, from
            // when it held a plain `String` rather than a tree.
            LegacyText(String),
            Current(Tagged),
        }

        Ok(match ValueDe::deserialize(deserializer)? {
            ValueDe::Legacy(n) => Value::Number { value: n },
            ValueDe::LegacyText(s) => Value::Text { value: s },
            ValueDe::Current(Tagged::Number { value }) => Value::Number { value },
            ValueDe::Current(Tagged::Text { value }) => Value::Text { value },
            ValueDe::Current(Tagged::Bool) => Value::Bool,
            ValueDe::Current(Tagged::Op { op, args, saved }) => Value::Op { op, args, saved },
            ValueDe::Current(Tagged::Var { name }) => Value::Var { name },
            ValueDe::Current(Tagged::Param { name }) => Value::Param { name },
            ValueDe::Current(Tagged::Call {
                block_id,
                args,
                branches,
                saved,
            }) => Value::Call {
                block_id,
                args,
                branches,
                saved,
            },
            ValueDe::Current(Tagged::BinaryOp {
                op,
                lhs,
                rhs,
                saved,
            }) => Value::Op {
                op,
                args: vec![*lhs, *rhs],
                saved,
            },
            ValueDe::Current(Tagged::Join { args, saved }) => Value::Op {
                op: Op::Join,
                args,
                saved,
            },
        })
    }
}
