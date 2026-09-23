//! Custom blocks ("My Blocks"): the prototype a user defines, and the
//! pieces it's built from.

use serde::{Deserialize, Serialize};

/// What kind of value an input slot expects. Drives the blank a fresh call
/// site's argument gets, and so whether it renders as a capsule or a boolean
/// hexagon. `#[serde(default)]` keeps older saves loading as `Any`.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize, Default)]
pub enum InputValueType {
    #[default]
    Any,
    Bool,
}

/// One piece of a custom block's prototype: static label text, a named
/// input read in the body via `Value::Param`, or a named branch callback
/// supplied at the call site and run by the host's branch-execution block.
/// `id` never changes, so it still identifies the piece after a rename.
#[derive(Debug, Clone, PartialEq, Hash, Serialize, Deserialize)]
#[serde(tag = "kind")]
pub enum BlockPiece {
    Label {
        id: String,
        text: String,
    },
    Input {
        id: String,
        name: String,
        #[serde(default)]
        value_type: InputValueType,
    },
    Branch {
        id: String,
        name: String,
    },
}

impl BlockPiece {
    pub fn id(&self) -> &str {
        match self {
            BlockPiece::Label { id, .. } | BlockPiece::Input { id, .. } | BlockPiece::Branch { id, .. } => id,
        }
    }
}

/// What a custom block's call site looks like: a stackable instruction
/// (`Normal`), one with no bottom notch (`Ending`), or a reporter returning
/// a number-or-text oval (`ReturnsValue`) or a boolean hexagon
/// (`ReturnsBool`). Each pair is mutually exclusive in the "Make a Block" UI.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Default)]
pub enum BlockShape {
    #[default]
    Normal,
    Ending,
    ReturnsValue,
    ReturnsBool,
}

impl BlockShape {
    /// True for either reporter shape - gates whether `Value::Call` nodes on
    /// this block are meaningful. Which of the two is a rendering concern
    /// only; `Value::eval` is dynamically typed either way.
    pub fn returns_value(self) -> bool {
        matches!(self, BlockShape::ReturnsValue | BlockShape::ReturnsBool)
    }

    /// True only for the no-bottom-notch command shape.
    pub fn is_ending(self) -> bool {
        matches!(self, BlockShape::Ending)
    }
}

/// Decodes either the old `returns_value: bool` (`true` becoming
/// `ReturnsValue`) or today's `shape` tag, whichever the file has.
impl<'de> Deserialize<'de> for BlockShape {
    fn deserialize<D>(deserializer: D) -> Result<Self, D::Error>
    where
        D: serde::Deserializer<'de>,
    {
        #[derive(Deserialize)]
        #[serde(untagged)]
        enum ShapeDe {
            Legacy(bool),
            Current(String),
        }
        Ok(match ShapeDe::deserialize(deserializer)? {
            ShapeDe::Legacy(true) => BlockShape::ReturnsValue,
            ShapeDe::Legacy(false) => BlockShape::Normal,
            ShapeDe::Current(s) => match s.as_str() {
                "Normal" => BlockShape::Normal,
                "Ending" => BlockShape::Ending,
                "ReturnsValue" => BlockShape::ReturnsValue,
                "ReturnsBool" => BlockShape::ReturnsBool,
                other => {
                    return Err(serde::de::Error::unknown_variant(
                        other,
                        &["Normal", "Ending", "ReturnsValue", "ReturnsBool"],
                    ));
                }
            },
        })
    }
}

/// A user-defined custom block - the prototype only. Its body lives in a
/// separate [`crate::graph::Strand`] headed by the host's block-header kind.
#[derive(Debug, Clone, PartialEq, Hash, Serialize, Deserialize)]
pub struct BlockDef {
    pub id: String,
    pub pieces: Vec<BlockPiece>,
    #[serde(alias = "returns_value")]
    pub shape: BlockShape,
    /// User-selected accent for the block's icon and hover outline. The
    /// default preserves the established blue treatment for older documents.
    #[serde(default = "default_block_color")]
    pub color: String,
}

/// The legacy/default custom-block accent. Kept as a function so serde can
/// supply it when loading documents saved before custom colors existed.
pub fn default_block_color() -> String {
    "#4C97FF".to_string()
}

/// Canonicalizes the one color format that gets persisted and handed to
/// CSS. `None` for anything that isn't safe to use as a block accent.
pub fn normalize_block_color(color: &str) -> Option<String> {
    let color = color.trim();
    (color.len() == 7
        && color.starts_with('#')
        && color[1..].bytes().all(|b| b.is_ascii_hexdigit()))
    .then(|| color.to_ascii_uppercase())
}

impl BlockDef {
    /// Declared input names, in prototype order - the positional key a call
    /// site's `args` line up against.
    pub fn input_names(&self) -> impl Iterator<Item = &str> {
        self.pieces.iter().filter_map(|p| match p {
            BlockPiece::Input { name, .. } => Some(name.as_str()),
            BlockPiece::Label { .. } | BlockPiece::Branch { .. } => None,
        })
    }

    /// Declared branch names, in prototype order - the positional key a call
    /// site's branch bodies line up against, and what the host's
    /// branch-execution block looks up at runtime.
    pub fn branch_names(&self) -> impl Iterator<Item = &str> {
        self.pieces.iter().filter_map(|p| match p {
            BlockPiece::Branch { name, .. } => Some(name.as_str()),
            BlockPiece::Label { .. } | BlockPiece::Input { .. } => None,
        })
    }

    /// Declared input types, in prototype order - positionally aligned with
    /// [`BlockDef::input_names`] and a call site's `args`.
    pub fn input_types(&self) -> impl Iterator<Item = InputValueType> + '_ {
        self.pieces.iter().filter_map(|p| match p {
            BlockPiece::Input { value_type, .. } => Some(*value_type),
            BlockPiece::Label { .. } | BlockPiece::Branch { .. } => None,
        })
    }

    /// Validates a candidate `pieces` list: the trimmed labels must spell
    /// out a name, every input needs a non-empty, unique one, and branch
    /// callbacks share that same name pool (a branch runs in the body's
    /// scope, so its name must not collide with an input's).
    pub fn validate_pieces(pieces: &[BlockPiece]) -> Result<(), String> {
        let flat_label: String = pieces
            .iter()
            .filter_map(|p| match p {
                BlockPiece::Label { text, .. } => Some(text.trim()),
                BlockPiece::Input { .. } | BlockPiece::Branch { .. } => None,
            })
            .collect::<Vec<_>>()
            .join(" ");
        if flat_label.trim().is_empty() {
            return Err("Give the block a name".to_string());
        }
        if pieces.iter().filter(|p| matches!(p, BlockPiece::Branch { .. })).count() > u8::MAX as usize {
            return Err("A block can have at most 255 branches".to_string());
        }
        let mut seen = std::collections::HashSet::new();
        for p in pieces {
            match p {
                BlockPiece::Input { name, .. } => {
                    let trimmed = name.trim();
                    if trimmed.is_empty() {
                        return Err("Every input needs a name".to_string());
                    }
                    if !seen.insert(trimmed) {
                        return Err(format!("Input name \"{trimmed}\" is used more than once"));
                    }
                }
                BlockPiece::Branch { name, .. } => {
                    let trimmed = name.trim();
                    if trimmed.is_empty() {
                        return Err("Every branch needs a name".to_string());
                    }
                    if !seen.insert(trimmed) {
                        return Err(format!("Branch name \"{trimmed}\" is used more than once"));
                    }
                }
                BlockPiece::Label { .. } => {}
            }
        }
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn legacy_returns_value_bool_migrates_to_a_shape() {
        assert_eq!(
            serde_json::from_str::<BlockShape>("true").unwrap(),
            BlockShape::ReturnsValue
        );
        assert_eq!(
            serde_json::from_str::<BlockShape>("false").unwrap(),
            BlockShape::Normal
        );
    }

    #[test]
    fn block_color_must_be_six_digit_hex() {
        assert_eq!(
            normalize_block_color(" #4c97ff "),
            Some("#4C97FF".to_string())
        );
        assert_eq!(normalize_block_color("red"), None);
        assert_eq!(normalize_block_color("#fff"), None);
        assert_eq!(normalize_block_color("#12345g"), None);
    }

    #[test]
    fn validate_pieces_rejects_blank_and_duplicate_names() {
        let label = |text: &str| BlockPiece::Label {
            id: "l".to_string(),
            text: text.to_string(),
        };
        let input = |id: &str, name: &str| BlockPiece::Input {
            id: id.to_string(),
            name: name.to_string(),
            value_type: InputValueType::Any,
        };
        assert!(BlockDef::validate_pieces(&[label("jump")]).is_ok());
        assert!(BlockDef::validate_pieces(&[label("  ")]).is_err());
        assert!(BlockDef::validate_pieces(&[label("jump"), input("a", " ")]).is_err());
        assert!(
            BlockDef::validate_pieces(&[label("jump"), input("a", "x"), input("b", "x")]).is_err()
        );
    }

    #[test]
    fn branch_pieces_round_trip_and_validate() {
        let branch = |id: &str, name: &str| BlockPiece::Branch {
            id: id.to_string(),
            name: name.to_string(),
        };
        let label = |text: &str| BlockPiece::Label {
            id: "l".to_string(),
            text: text.to_string(),
        };
        // The exact shape the Make-a-Block dialog sends: must deserialize,
        // not fail with "unknown variant `Branch`".
        let pieces: Vec<BlockPiece> = serde_json::from_value(serde_json::json!([
            { "kind": "Label", "id": "l", "text": "run" },
            { "kind": "Branch", "id": "b1", "name": "callback" },
        ]))
        .expect("Branch pieces must deserialize");
        assert!(BlockDef::validate_pieces(&pieces).is_ok());
        assert_eq!(
            pieces[1].id(),
            "b1",
            "Branch keeps a stable id for call-site reconciliation"
        );
        let def = BlockDef {
            id: "b".to_string(),
            pieces,
            shape: BlockShape::Normal,
            color: default_block_color(),
        };
        assert_eq!(
            def.branch_names().collect::<Vec<_>>(),
            vec!["callback"],
            "branch names line up positionally against call-site bodies"
        );
        assert!(def.input_names().next().is_none());
        // Branches share the name pool with inputs.
        assert!(
            BlockDef::validate_pieces(&[
                label("run"),
                branch("b1", "x"),
                BlockPiece::Input {
                    id: "i".to_string(),
                    name: "x".to_string(),
                    value_type: InputValueType::Any,
                },
            ])
            .is_err()
        );
    }
}
