//! [`BlockKind`], the one extension point a host app implements, plus the
//! [`Instruction`] wrapper and the traversals built on it.

use crate::graph::block::{BlockDef, InputValueType};
use crate::value::Value;
use serde::de::DeserializeOwned;
use serde::{Deserialize, Serialize};
use std::fmt::Debug;
use std::hash::Hash;

/// The host app's block vocabulary - one variant per block its palette can
/// drop. An app only describes where its values and bodies live; every walk
/// over them is written once, here. Only [`BlockKind::visit_values_mut`] has
/// no default.
pub trait BlockKind:
    Clone + Debug + PartialEq + Hash + Serialize + DeserializeOwned + Sized
{
    /// How many nested instruction lists one kind can own - `2` covers an
    /// if/else. [`BlockKind::body`] is asked for every slot below this, gaps
    /// included, so a kind with a dynamic number of branches sets `u8::MAX`
    /// and keeps its count at 255 or fewer.
    const BODY_SLOTS: u8 = 2;

    /// What the app calls its header blocks, for the placement errors the
    /// editor raises ("Can't attach a block above a *When Ran* block").
    const HEADER_LABEL: &'static str = "header";

    /// Every [`Value`] this kind owns directly, with the slot's declared
    /// type; nested bodies are walked separately. `Bool` marks the slots
    /// [`Value::migrate_bool_slots`] may need to repair.
    fn visit_values_mut(&mut self, f: &mut dyn FnMut(&mut Value, InputValueType));

    /// True for "header" blocks - must be first in their strand, nothing may
    /// stack above them, and they render with a flat top edge.
    fn is_header(&self) -> bool {
        false
    }

    /// Read-only counterpart to [`BlockKind::body_mut`].
    fn body(&self, _slot: u8) -> Option<&Vec<Instruction<Self>>> {
        None
    }

    /// The nested instruction list for `slot` - an `if`'s body (`0`), or an
    /// if/else's two branches (`0`/`1`). The primitive nesting builds on.
    fn body_mut(&mut self, _slot: u8) -> Option<&mut Vec<Instruction<Self>>> {
        None
    }

    /// Every variable, list and dict name this kind holds as plain text
    /// rather than in a value: a "set" block's target, each output of a
    /// block that writes several, a list block's list. Renames, packs and
    /// usage scans all go through this, so one kind may report any number.
    /// The default reports the three single-target methods below.
    fn visit_refs_mut(&mut self, f: &mut dyn FnMut(RefKind, &mut String)) {
        if let Some(name) = self.variable_target_mut() {
            f(RefKind::Variable, name);
        }
        if let Some(name) = self.list_target_mut() {
            f(RefKind::List, name);
        }
        if let Some(name) = self.dict_target_mut() {
            f(RefKind::Dict, name);
        }
    }

    /// Read-only counterpart to [`BlockKind::visit_refs_mut`]. The default
    /// visits a clone; override it if that clone is costly.
    fn visit_refs(&self, f: &mut dyn FnMut(RefKind, &str)) {
        self.clone().visit_refs_mut(&mut |kind, name| f(kind, name));
    }

    /// Compatibility path: one variable name this kind writes. Only read by
    /// the default [`BlockKind::visit_refs_mut`]; new hosts override that.
    fn variable_target_mut(&mut self) -> Option<&mut String> {
        None
    }

    /// Compatibility path: one list name this kind writes. See
    /// [`BlockKind::variable_target_mut`].
    fn list_target_mut(&mut self) -> Option<&mut String> {
        None
    }

    /// Compatibility path: one dict name this kind writes. See
    /// [`BlockKind::variable_target_mut`].
    fn dict_target_mut(&mut self) -> Option<&mut String> {
        None
    }

    /// True if this is a command-position invocation of `block_id`.
    fn calls_block(&self, _block_id: &str) -> bool {
        false
    }

    /// The custom block this kind invokes in command position, if any, so a
    /// paste can tell which definitions it needs.
    fn called_block(&self) -> Option<&str> {
        None
    }

    /// The argument list of a command-position invocation of `block_id`.
    fn call_args_mut(&mut self, _block_id: &str) -> Option<&mut Vec<Value>> {
        None
    }

    /// The branch bodies of a command-position invocation of `block_id`, in
    /// the definition's branch order, so editing the block can keep them
    /// with their branch.
    fn call_branches_mut(&mut self, _block_id: &str) -> Option<&mut Vec<Vec<Instruction<Self>>>> {
        None
    }

    /// The custom block whose body this kind heads, if it's a block header.
    fn block_header_id(&self) -> Option<&str> {
        None
    }

    /// The value tree a field id names on this kind, so a drag or a typed
    /// edit reaches the right slot. Field ids are opaque strings.
    fn value_slot_mut(&mut self, _field: &str) -> Option<&mut Value> {
        None
    }

    /// The blank a top-level field restores to when nothing was shadowed;
    /// `None` means a plain zero. `blocks` is there for a call site, whose
    /// declared types live on the [`BlockDef`], not on the instruction.
    fn blank_field_value(&self, _field: &str, _blocks: &[BlockDef]) -> Option<Value> {
        None
    }

    /// True for fields that only accept whole numbers, so typed input is
    /// parsed as an integer.
    fn field_requires_integer(&self, _field: &str) -> bool {
        false
    }
}

/// What a name in [`BlockKind::visit_refs_mut`] refers to. Each has its
/// own namespace, so a rename only follows names of its own kind.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum RefKind {
    Variable,
    List,
    Dict,
}

fn new_instruction_id() -> String {
    crate::graph::new_id()
}

/// The wrapper every instruction is stored as: `id` is a stable identity
/// that survives drags and reorders, and is what comments attach to.
/// Equality and hashing ignore it and compare `kind` alone.
#[derive(Debug, Clone)]
pub struct Instruction<K> {
    pub id: String,
    pub kind: K,
}

impl<K> Instruction<K> {
    pub fn new(kind: K) -> Self {
        Self {
            id: new_instruction_id(),
            kind,
        }
    }
}

impl<K: BlockKind> Instruction<K> {
    pub fn is_header(&self) -> bool {
        self.kind.is_header()
    }

    pub fn body(&self, slot: u8) -> Option<&Vec<Instruction<K>>> {
        self.kind.body(slot)
    }

    pub fn body_mut(&mut self, slot: u8) -> Option<&mut Vec<Instruction<K>>> {
        self.kind.body_mut(slot)
    }

    /// Pre-order walk over this instruction and everything nested inside it.
    /// Every other traversal here is written in terms of this one.
    pub fn walk_mut(&mut self, f: &mut dyn FnMut(&mut Instruction<K>)) {
        f(self);
        for slot in 0..K::BODY_SLOTS {
            if let Some(body) = self.kind.body_mut(slot) {
                for child in body.iter_mut() {
                    child.walk_mut(&mut *f);
                }
            }
        }
    }

    /// Read-only pre-order walk - counterpart to [`Instruction::walk_mut`].
    pub fn walk(&self, f: &mut dyn FnMut(&Instruction<K>)) {
        f(self);
        for slot in 0..K::BODY_SLOTS {
            if let Some(body) = self.kind.body(slot) {
                for child in body {
                    child.walk(&mut *f);
                }
            }
        }
    }

    /// Every value in this instruction and everything nested inside it.
    pub fn visit_values_mut(&mut self, f: &mut dyn FnMut(&mut Value, InputValueType)) {
        self.walk_mut(&mut |ins| ins.kind.visit_values_mut(&mut *f));
    }

    /// Every name of `kind` this instruction and its nested bodies hold,
    /// via [`BlockKind::visit_refs_mut`]. Reads inside values aren't visited.
    pub fn rename_refs(&mut self, kind: RefKind, old: &str, new: &str) {
        self.walk_mut(&mut |ins| {
            ins.kind.visit_refs_mut(&mut |k, name| {
                if k == kind && name == old {
                    *name = new.to_string();
                }
            });
        });
    }

    /// Read-only walk over every name this instruction and its nested
    /// bodies hold, via [`BlockKind::visit_refs`].
    pub fn walk_refs(&self, f: &mut dyn FnMut(RefKind, &str)) {
        self.walk(&mut |ins| ins.kind.visit_refs(&mut *f));
    }

    /// Renames variable reads, plus every variable name the block holds.
    pub fn rename_var(&mut self, old: &str, new: &str) {
        self.rename_refs(RefKind::Variable, old, new);
        self.visit_values_mut(&mut |value, _| value.rename_var(old, new));
    }

    /// Renames list references: every list name a block holds plus reporter
    /// name args inside every value tree.
    pub fn rename_list(&mut self, old: &str, new: &str) {
        self.rename_refs(RefKind::List, old, new);
        self.visit_values_mut(&mut |value, _| {
            crate::graph::lists::rename_list_in_value(value, old, new)
        });
    }

    /// Renames dict references: every dict name a block holds plus reporter
    /// name args inside every value tree.
    pub fn rename_dict(&mut self, old: &str, new: &str) {
        self.rename_refs(RefKind::Dict, old, new);
        self.visit_values_mut(&mut |value, _| {
            crate::graph::dicts::rename_dict_in_value(value, old, new)
        });
    }

    /// Renames every `Value::Param` leaf reading `old` to `new`, keeping a
    /// block's body working after one of its inputs is renamed.
    pub fn rename_param(&mut self, old: &str, new: &str) {
        self.visit_values_mut(&mut |value, _| value.rename_param(old, new));
    }

    /// Repairs boolean slots poisoned by a legacy blank. Which slots are
    /// boolean comes from [`BlockKind::visit_values_mut`]'s type hints.
    pub fn migrate_bool_slots(&mut self) {
        self.visit_values_mut(&mut |value, value_type| {
            value.migrate_bool_slots(value_type == InputValueType::Bool)
        });
    }

    /// Applies `f` to the arguments of every call of `block_id`, wherever
    /// nested - keeps call sites aligned when a block's inputs change.
    pub fn for_each_call_args_mut(&mut self, block_id: &str, f: &mut dyn FnMut(&mut Vec<Value>)) {
        self.walk_mut(&mut |ins| {
            if let Some(args) = ins.kind.call_args_mut(block_id) {
                f(args);
            }
            ins.kind
                .visit_values_mut(&mut |value, _| value.for_each_call_args_mut(block_id, &mut *f));
        });
    }

    /// Applies `f_ins` to the branch bodies of every command-position call of
    /// `block_id`, and `f_val` to those of every reporter call, wherever nested.
    pub fn for_each_call_branches_mut(
        &mut self,
        block_id: &str,
        f_ins: &mut dyn FnMut(&mut Vec<Vec<Instruction<K>>>),
        f_val: &mut dyn FnMut(&mut Vec<Vec<serde_json::Value>>),
    ) {
        self.walk_mut(&mut |ins| {
            if let Some(branches) = ins.kind.call_branches_mut(block_id) {
                f_ins(branches);
            }
            ins.kind
                .visit_values_mut(&mut |value, _| value.for_each_call_branches_mut(block_id, &mut *f_val));
        });
    }

    /// Replaces every `Value::Call` on `block_id` with a plain `0` leaf. A
    /// command-position call is the caller's to drop.
    pub fn scrub_block_calls(&mut self, block_id: &str) {
        self.visit_values_mut(&mut |value, _| value.scrub_block_calls(block_id));
    }
}

impl<K: PartialEq> PartialEq for Instruction<K> {
    fn eq(&self, other: &Self) -> bool {
        self.kind == other.kind
    }
}

impl<K: Hash> Hash for Instruction<K> {
    fn hash<H: std::hash::Hasher>(&self, state: &mut H) {
        self.kind.hash(state);
    }
}

/// Stored as `{"id": ..., "kind": ...}`, or flat inside
/// [`crate::graph::to_frontend`].
impl<K: Serialize> Serialize for Instruction<K> {
    fn serialize<S: serde::Serializer>(&self, serializer: S) -> Result<S::Ok, S::Error> {
        use serde::ser::{Error, SerializeStruct};
        if crate::graph::wire::flat() {
            return crate::graph::wire::flatten(&self.id, &self.kind)
                .map_err(S::Error::custom)?
                .serialize(serializer);
        }
        let mut out = serializer.serialize_struct("Instruction", 2)?;
        out.serialize_field("id", &self.id)?;
        out.serialize_field("kind", &self.kind)?;
        out.end()
    }
}

/// Stored shape for [`Instruction`]: `{"id": ..., "kind": ...}`, or a bare
/// kind from before ids existed, which gets a fresh one on load.
#[derive(Deserialize)]
#[serde(untagged, bound(deserialize = "K: Deserialize<'de>"))]
enum InstructionEnvelope<K> {
    Current { id: String, kind: K },
    Legacy(K),
}

impl<'de, K: Deserialize<'de>> Deserialize<'de> for Instruction<K> {
    fn deserialize<D: serde::Deserializer<'de>>(deserializer: D) -> Result<Self, D::Error> {
        if crate::graph::wire::flat() {
            let json = serde_json::Value::deserialize(deserializer)?;
            return crate::graph::wire::unflatten(json).map_err(serde::de::Error::custom);
        }
        Ok(match InstructionEnvelope::deserialize(deserializer)? {
            InstructionEnvelope::Current { id, kind } => Instruction { id, kind },
            InstructionEnvelope::Legacy(kind) => Instruction::new(kind),
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::graph::BlockGraph;

    #[derive(Debug, Clone, PartialEq, Hash, Serialize, Deserialize)]
    enum Block {
        Set(String, Value),
        // Writes two variables and a list, like a "find" block.
        Find { x: String, y: String, hits: String },
        Repeat(Vec<Instruction<Block>>),
    }

    impl BlockKind for Block {
        fn visit_values_mut(&mut self, f: &mut dyn FnMut(&mut Value, InputValueType)) {
            if let Block::Set(_, value) = self {
                f(value, InputValueType::Any);
            }
        }
        fn body(&self, slot: u8) -> Option<&Vec<Instruction<Block>>> {
            match (self, slot) {
                (Block::Repeat(body), 0) => Some(body),
                _ => None,
            }
        }
        fn body_mut(&mut self, slot: u8) -> Option<&mut Vec<Instruction<Block>>> {
            match (self, slot) {
                (Block::Repeat(body), 0) => Some(body),
                _ => None,
            }
        }
        fn visit_refs_mut(&mut self, f: &mut dyn FnMut(RefKind, &mut String)) {
            match self {
                Block::Set(name, _) => f(RefKind::Variable, name),
                Block::Find { x, y, hits } => {
                    f(RefKind::Variable, x);
                    f(RefKind::Variable, y);
                    f(RefKind::List, hits);
                }
                Block::Repeat(_) => {}
            }
        }
    }

    // Only the single-target compatibility method.
    #[derive(Debug, Clone, PartialEq, Hash, Serialize, Deserialize)]
    struct Legacy(String);

    impl BlockKind for Legacy {
        fn visit_values_mut(&mut self, _: &mut dyn FnMut(&mut Value, InputValueType)) {}
        fn variable_target_mut(&mut self) -> Option<&mut String> {
            Some(&mut self.0)
        }
    }

    fn var(name: &str) -> Value {
        Value::Var { name: name.into() }
    }

    fn graph() -> BlockGraph<Block> {
        let mut graph = BlockGraph::new();
        for name in ["a", "b", "c"] {
            graph.create_variable(name).unwrap();
        }
        let find = Block::Find {
            x: "a".into(),
            y: "b".into(),
            hits: "a".into(),
        };
        let nested = Instruction::new(Block::Repeat(vec![
            Instruction::new(find.clone()),
            Instruction::new(Block::Set("c".into(), var("b"))),
        ]));
        graph.strands.push(crate::graph::Strand::with_instructions(
            0,
            0,
            vec![Instruction::new(find), nested],
        ));
        graph
    }

    fn refs(graph: &BlockGraph<Block>) -> Vec<(RefKind, String)> {
        let mut out = Vec::new();
        for ins in &graph.strands[0].instructions {
            ins.walk_refs(&mut |kind, name| out.push((kind, name.to_string())));
        }
        out
    }

    #[test]
    fn rename_reaches_every_output_including_nested_ones() {
        let mut graph = graph();
        graph.rename_variable("a", "ax").unwrap();
        graph.rename_variable("b", "by").unwrap();
        use RefKind::*;
        let expect = |list: &str| {
            vec![
                (Variable, "ax".to_string()),
                (Variable, "by".to_string()),
                (List, list.to_string()),
                (Variable, "ax".to_string()),
                (Variable, "by".to_string()),
                (List, list.to_string()),
                (Variable, "c".to_string()),
            ]
        };
        // The list named "a" is a different thing and keeps its name.
        assert_eq!(refs(&graph), expect("a"));
        let Block::Repeat(body) = &graph.strands[0].instructions[1].kind else {
            panic!()
        };
        assert_eq!(body[1].kind, Block::Set("c".into(), var("by")));
        graph.create_list("a").unwrap();
        graph.rename_list("a", "hits").unwrap();
        assert_eq!(refs(&graph), expect("hits"));
    }

    #[test]
    fn single_target_hosts_keep_working() {
        let mut ins = Instruction::new(Legacy("a".into()));
        let mut seen = Vec::new();
        ins.walk_refs(&mut |kind, name| seen.push((kind, name.to_string())));
        assert_eq!(seen, [(RefKind::Variable, "a".to_string())]);
        ins.rename_var("a", "b");
        assert_eq!(ins.kind, Legacy("b".into()));
        ins.rename_list("b", "c");
        assert_eq!(ins.kind, Legacy("b".into()));
    }
}
