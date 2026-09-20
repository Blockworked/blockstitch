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
    /// if/else. [`BlockKind::body`] is asked for every slot below this.
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

    /// The variable name this kind *writes* (a "set"/"change" block), so a
    /// rename can follow it. Reads live in values and need nothing here.
    fn variable_target_mut(&mut self) -> Option<&mut String> {
        None
    }

    /// True if this is a command-position invocation of `block_id`.
    fn calls_block(&self, _block_id: &str) -> bool {
        false
    }

    /// The argument list of a command-position invocation of `block_id`.
    fn call_args_mut(&mut self, _block_id: &str) -> Option<&mut Vec<Value>> {
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

fn new_instruction_id() -> String {
    crate::graph::new_id()
}

/// The wrapper every instruction is stored as: `id` is a stable identity
/// that survives drags and reorders, and is what comments attach to.
/// Equality and hashing ignore it and compare `kind` alone.
#[derive(Debug, Clone, Serialize)]
#[serde(bound(serialize = "K: Serialize"))]
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

    /// Renames variable reads, plus a "set"/"change" block's own target name.
    pub fn rename_var(&mut self, old: &str, new: &str) {
        self.walk_mut(&mut |ins| {
            if let Some(target) = ins.kind.variable_target_mut()
                && target == old
            {
                *target = new.to_string();
            }
            ins.kind
                .visit_values_mut(&mut |value, _| value.rename_var(old, new));
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
            ins.kind.visit_values_mut(&mut |value, _| {
                value.for_each_call_args_mut(block_id, &mut *f)
            });
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

/// Wire shape for [`Instruction`]: `{"id": ..., "kind": ...}`, or a bare
/// kind from before ids existed, which gets a fresh one on load.
#[derive(Deserialize)]
#[serde(untagged, bound(deserialize = "K: Deserialize<'de>"))]
enum InstructionEnvelope<K> {
    Current { id: String, kind: K },
    Legacy(K),
}

impl<'de, K: Deserialize<'de>> Deserialize<'de> for Instruction<K> {
    fn deserialize<D: serde::Deserializer<'de>>(deserializer: D) -> Result<Self, D::Error> {
        Ok(match InstructionEnvelope::deserialize(deserializer)? {
            InstructionEnvelope::Current { id, kind } => Instruction { id, kind },
            InstructionEnvelope::Legacy(kind) => Instruction::new(kind),
        })
    }
}
