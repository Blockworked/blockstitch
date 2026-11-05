//! Evaluating a value tree to a result.

use super::*;

/// 1-based char index of the first occurrence of `needle` in `haystack`, or
/// `0` if not found/empty/too long. Scans by char, not byte, for multi-byte text.
pub(super) fn char_index_of(haystack: &str, needle: &str) -> usize {
    let h: Vec<char> = haystack.chars().collect();
    let n: Vec<char> = needle.chars().collect();
    if n.is_empty() || n.len() > h.len() {
        return 0;
    }
    (0..=h.len() - n.len())
        .find(|&i| h[i..i + n.len()] == n[..])
        .map_or(0, |i| i + 1)
}

/// Same as [`char_index_of`], but the last occurrence.
pub(super) fn char_last_index_of(haystack: &str, needle: &str) -> usize {
    let h: Vec<char> = haystack.chars().collect();
    let n: Vec<char> = needle.chars().collect();
    if n.is_empty() || n.len() > h.len() {
        return 0;
    }
    (0..=h.len() - n.len())
        .rev()
        .find(|&i| h[i..i + n.len()] == n[..])
        .map_or(0, |i| i + 1)
}

/// `Op::Eq`'s comparison rule: numeric if both sides parse as a number,
/// otherwise a text comparison (mirrors Scratch's loose `=`).
pub(super) fn values_equal(l: &Evaluated, r: &Evaluated) -> bool {
    match (l.as_number(), r.as_number()) {
        (Ok(ln), Ok(rn)) => ln == rn,
        _ => l.as_text() == r.as_text(),
    }
}

impl Value {
    pub fn eval(&self) -> Result<Evaluated, String> {
        match self {
            Value::Number { value } => Ok(Evaluated::Number(*value)),
            Value::Text { value } => Ok(Evaluated::Text(value.clone())),
            // The "nothing plugged in" state of a boolean slot acts as false.
            Value::Bool => Ok(Evaluated::Bool(false)),
            // `resolve_vars` runs first at every real call site; reaching
            // here means that step was skipped, which is a bug.
            Value::Var { .. } => Err("unresolved variable reference".to_string()),
            // Same invariant as `Var`: resolving these means executing
            // instructions, which this module can't do. It also keeps a
            // preview's best-effort eval safe - a call errors, never runs.
            Value::Param { .. } => Err("unresolved parameter reference".to_string()),
            Value::Call { .. } => Err("custom block calls can't be evaluated directly".to_string()),
            Value::Op {
                op: Op::Join, args, ..
            } => {
                let mut s = String::new();
                for a in args {
                    s.push_str(&a.eval_text()?);
                }
                Ok(Evaluated::Text(s))
            }
            Value::Op {
                op: Op::NewLine, ..
            } => Ok(Evaluated::Text("\n".to_string())),
            Value::Op { op: Op::Tab, .. } => Ok(Evaluated::Text("\t".to_string())),
            Value::Op {
                op: Op::Length,
                args,
                ..
            } => Ok(Evaluated::Number(
                args[0].eval_text()?.chars().count() as f64
            )),
            Value::Op {
                op: Op::IndexOf,
                args,
                ..
            } => {
                let needle = args[0].eval_text()?;
                let haystack = args[1].eval_text()?;
                Ok(Evaluated::Number(char_index_of(&haystack, &needle) as f64))
            }
            Value::Op {
                op: Op::LastIndexOf,
                args,
                ..
            } => {
                let needle = args[0].eval_text()?;
                let haystack = args[1].eval_text()?;
                Ok(Evaluated::Number(
                    char_last_index_of(&haystack, &needle) as f64
                ))
            }
            Value::Op {
                op: Op::LetterOf,
                args,
                ..
            } => {
                let index = args[0].eval_number()? as i64;
                let text = args[1].eval_text()?;
                let chars: Vec<char> = text.chars().collect();
                if index < 1 || index as usize > chars.len() {
                    return Err(format!(
                        "letter {index} is out of range for a {}-character value",
                        chars.len()
                    ));
                }
                Ok(Evaluated::Text(chars[index as usize - 1].to_string()))
            }
            Value::Op {
                op: Op::Case, args, ..
            } => {
                let text = args[0].eval_text()?;
                let upper = args[1].eval_text()? == "Upper";
                Ok(Evaluated::Text(if upper {
                    text.to_uppercase()
                } else {
                    text.to_lowercase()
                }))
            }
            Value::Op {
                op: Op::Round,
                args,
                ..
            } => Ok(Evaluated::Number(args[0].eval_number()?.round())),
            Value::Op {
                op: Op::Math, args, ..
            } => {
                let function = args[0].eval_text()?;
                let n = args[1].eval_number()?;
                let degrees_to_radians = std::f64::consts::PI / 180.0;
                let radians_to_degrees = 180.0 / std::f64::consts::PI;
                let result = match function.as_str() {
                    "Abs" => n.abs(),
                    "Floor" => n.floor(),
                    "Ceiling" => n.ceil(),
                    "Sign" => {
                        if n > 0.0 {
                            1.0
                        } else if n < 0.0 {
                            -1.0
                        } else {
                            0.0
                        }
                    }
                    "Sqrt" => n.sqrt(),
                    "Sin" => (n * degrees_to_radians).sin(),
                    "Cos" => (n * degrees_to_radians).cos(),
                    "Tan" => (n * degrees_to_radians).tan(),
                    "Asin" => n.asin() * radians_to_degrees,
                    "Acos" => n.acos() * radians_to_degrees,
                    "Atan" => n.atan() * radians_to_degrees,
                    "Ln" => n.ln(),
                    "Log" => n.log10(),
                    "Log2" => n.log2(),
                    "EPower" => n.exp(),
                    "TenPower" => 10.0_f64.powf(n),
                    other => return Err(format!("unknown math function '{other}'")),
                };
                Ok(Evaluated::Number(result))
            }
            Value::Op { op: Op::True, .. } => Ok(Evaluated::Bool(true)),
            Value::Op { op: Op::False, .. } => Ok(Evaluated::Bool(false)),
            Value::Op {
                op: Op::CurrentTime,
                args,
                ..
            } => {
                use chrono::{Datelike, Timelike};
                let now = crate::sources::now();
                let n = match args[0].eval_text()?.as_str() {
                    "Year" => now.year() as f64,
                    "Month" => now.month() as f64,
                    "Date" => now.day() as f64,
                    // 1 (Sunday) through 7 (Saturday), matching Scratch's own
                    // "current (day of week)" numbering.
                    "DayOfWeek" => now.weekday().num_days_from_sunday() as f64 + 1.0,
                    "Hour" => now.hour() as f64,
                    "Minute" => now.minute() as f64,
                    "Second" => now.second() as f64,
                    other => return Err(format!("unknown current-time component '{other}'")),
                };
                Ok(Evaluated::Number(n))
            }
            Value::Op {
                op: Op::Not, args, ..
            } => Ok(Evaluated::Bool(!args[0].eval()?.as_bool())),
            Value::Op {
                op: Op::And, args, ..
            } => Ok(Evaluated::Bool(
                args[0].eval()?.as_bool() && args[1].eval()?.as_bool(),
            )),
            Value::Op {
                op: Op::Or, args, ..
            } => Ok(Evaluated::Bool(
                args[0].eval()?.as_bool() || args[1].eval()?.as_bool(),
            )),
            Value::Op {
                op: Op::Eq, args, ..
            } => Ok(Evaluated::Bool(values_equal(
                &args[0].eval()?,
                &args[1].eval()?,
            ))),
            Value::Op {
                op: Op::Neq, args, ..
            } => Ok(Evaluated::Bool(!values_equal(
                &args[0].eval()?,
                &args[1].eval()?,
            ))),
            Value::Op {
                op: Op::Gt, args, ..
            } => Ok(Evaluated::Bool(
                args[0].eval()?.as_number()? > args[1].eval()?.as_number()?,
            )),
            Value::Op {
                op: Op::Lt, args, ..
            } => Ok(Evaluated::Bool(
                args[0].eval()?.as_number()? < args[1].eval()?.as_number()?,
            )),
            Value::Op {
                op: Op::Gte, args, ..
            } => Ok(Evaluated::Bool(
                args[0].eval()?.as_number()? >= args[1].eval()?.as_number()?,
            )),
            Value::Op {
                op: Op::Lte, args, ..
            } => Ok(Evaluated::Bool(
                args[0].eval()?.as_number()? <= args[1].eval()?.as_number()?,
            )),
            // Host-registered operator: every arg is evaluated up front, so
            // an extension can't short-circuit the way `And`/`Or` do.
            Value::Op {
                op: Op::Ext(name),
                args,
                ..
            } => {
                let operator = ext_operator(name).ok_or_else(|| {
                    format!(
                        "unknown operator '{name}' - was the host's operator registry installed?"
                    )
                })?;
                let args = args
                    .iter()
                    .map(Value::eval)
                    .collect::<Result<Vec<_>, _>>()?;
                (operator.eval)(&args)
            }
            Value::Op { op, args, .. } => {
                let l = args[0].eval()?.as_number()?;
                let r = args[1].eval()?.as_number()?;
                let result = match op {
                    Op::Add => l + r,
                    Op::Sub => l - r,
                    Op::Mul => l * r,
                    Op::Div => {
                        if r == 0.0 {
                            return Err("division by zero".to_string());
                        }
                        l / r
                    }
                    Op::Mod => {
                        if r == 0.0 {
                            return Err("mod by zero".to_string());
                        }
                        l.rem_euclid(r)
                    }
                    Op::Random => {
                        let (lo, hi) = (l.min(r), l.max(r));
                        if l.fract() == 0.0 && r.fract() == 0.0 {
                            crate::sources::random_int(lo as i64, hi as i64) as f64
                        } else {
                            crate::sources::random_float(lo, hi)
                        }
                    }
                    other => unreachable!("{} matched above", other.name()),
                };
                Ok(Evaluated::Number(result))
            }
        }
    }

    /// Evaluates the tree and coerces the result to a number - the entry
    /// point every numeric instruction field actually calls.
    pub fn eval_number(&self) -> Result<f64, String> {
        self.eval()?.as_number()
    }

    /// Evaluates to a string - the entry point a text-typed field calls.
    /// Numeric results get stringified.
    pub fn eval_text(&self) -> Result<String, String> {
        Ok(self.eval()?.as_text())
    }

}
