//! Everything that sits on the canvas: instruction stacks, parked value
//! blocks, notes, and declared variables.

use crate::graph::instruction::{BlockKind, Instruction};
use crate::graph::new_id;
use crate::value::{Evaluated, Value};
use serde::{Deserialize, Serialize};

fn default_strand_id() -> String {
    new_id()
}

/// One draggable stack of instructions. It's an entry point when its first
/// instruction is a header ([`BlockKind::is_header`]); without one it stays
/// persisted but inert.
#[derive(Debug, Clone, PartialEq, Hash, Serialize, Deserialize)]
#[serde(bound(serialize = "K: Serialize", deserialize = "K: Deserialize<'de>"))]
pub struct Strand<K> {
    #[serde(default = "default_strand_id")]
    pub id: String,
    #[serde(default)]
    pub x: i32,
    #[serde(default)]
    pub y: i32,
    #[serde(default = "Vec::new")]
    pub instructions: Vec<Instruction<K>>,
}

impl<K> Strand<K> {
    /// A fresh, empty strand parked at `(x, y)`.
    pub fn new(x: i32, y: i32) -> Self {
        Self {
            id: new_id(),
            x,
            y,
            instructions: Vec::new(),
        }
    }

    /// A fresh strand parked at `(x, y)` holding `instructions`.
    pub fn with_instructions(x: i32, y: i32, instructions: Vec<Instruction<K>>) -> Self {
        Self {
            id: new_id(),
            x,
            y,
            instructions,
        }
    }
}

impl<K: BlockKind> Strand<K> {
    /// True when this stack is headed by a header block - i.e. it's an
    /// entry point or a custom block's body rather than a loose stack.
    pub fn starts_with_header(&self) -> bool {
        self.instructions.first().is_some_and(Instruction::is_header)
    }

    /// The custom block this strand is the body of, if any.
    pub fn block_header_id(&self) -> Option<&str> {
        self.instructions.first()?.kind.block_header_id()
    }
}

fn default_floating_value_id() -> String {
    new_id()
}

/// A value block sitting free on the canvas - where a value waits before or
/// after being placed into a field's slot.
#[derive(Debug, Clone, PartialEq, Hash, Serialize, Deserialize)]
pub struct FloatingValue {
    #[serde(default = "default_floating_value_id")]
    pub id: String,
    #[serde(default)]
    pub x: i32,
    #[serde(default)]
    pub y: i32,
    pub value: Value,
    /// The custom block whose header this value was dragged out of, set only
    /// for a `Value::Param` reporter (the one value kind that's meaningless
    /// elsewhere). Lets the frontend draw it with its declared shape.
    #[serde(default)]
    pub origin_block_id: Option<String>,
}

impl FloatingValue {
    pub fn new(x: i32, y: i32, value: Value, origin_block_id: Option<String>) -> Self {
        Self {
            id: new_id(),
            x,
            y,
            value,
            origin_block_id,
        }
    }
}

fn default_comment_id() -> String {
    new_id()
}

/// A floating, collapsible note: freestanding (`x`/`y` an absolute canvas
/// position) or pinned to an instruction (`x`/`y` an offset from wherever
/// that instruction renders, since only the frontend knows where that is).
#[derive(Debug, Clone, PartialEq, Hash, Serialize, Deserialize)]
pub struct Comment {
    #[serde(default = "default_comment_id")]
    pub id: String,
    #[serde(default)]
    pub x: i32,
    #[serde(default)]
    pub y: i32,
    #[serde(default)]
    pub text: String,
    #[serde(default)]
    pub collapsed: bool,
    #[serde(default)]
    pub attached_to: Option<String>,
}

impl Comment {
    pub fn new(x: i32, y: i32, text: String, attached_to: Option<String>) -> Self {
        Self {
            id: new_id(),
            x,
            y,
            text,
            collapsed: false,
            attached_to,
        }
    }
}

fn default_variable_value() -> Evaluated {
    Evaluated::Number(0.0)
}

/// A user-declared document-wide variable and its current value, persisted
/// with the document so it survives a restart.
#[derive(Debug, Clone, PartialEq, Hash, Serialize, Deserialize)]
pub struct VariableDef {
    pub name: String,
    #[serde(default = "default_variable_value")]
    pub value: Evaluated,
}
