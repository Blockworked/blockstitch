//! What a drag, a drop or a typed character does to a [`BlockGraph`]. Each
//! edit validates before it mutates, and none of them lock, save or notify.

use crate::editor::location::ValueLocation;
use crate::editor::path::{PathStep, resolve_body, resolve_body_mut};
use crate::graph::{
    BlockDef, BlockGraph, BlockKind, BlockPiece, BlockShape, Comment, FloatingValue, Instruction,
    Strand, normalize_block_color,
};
use crate::value::{Evaluated, Value, operator_kind};
use std::collections::HashMap;

/// Horizontal gap between a freshly spawned strand and the rightmost
/// existing one, so new stacks don't pile up on top of each other.
const NEW_STRAND_GAP: i32 = 260;

/// What [`BlockGraph::edit_value_text`] did with the typed text.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ValueEdit {
    /// The location doesn't resolve - nothing was written.
    Missing,
    /// A text slot took the input verbatim; text is always valid, so
    /// there's no buffer to keep.
    Text,
    /// A numeric slot. `parsed` is false for text that isn't a number yet
    /// (`"-"`, `"1e"`), which the host keeps in a [`crate::editor::ValueBuffers`].
    Number { parsed: bool },
}

impl<K: BlockKind> BlockGraph<K> {
    // ── Instructions ───────────────────────────────────────────────────────

    /// The instruction `path` addresses within `strand_id`.
    pub fn instruction_at(&self, strand_id: &str, path: &[PathStep]) -> Option<&Instruction<K>> {
        let strand = self.strand(strand_id)?;
        let (list, index) = resolve_body(&strand.instructions, path)?;
        list.get(index)
    }

    /// Mutable counterpart to [`BlockGraph::instruction_at`] - for an edit
    /// that rewrites one instruction in place rather than moving any.
    pub fn instruction_at_mut(
        &mut self,
        strand_id: &str,
        path: &[PathStep],
    ) -> Option<&mut Instruction<K>> {
        let strand = self.strand_mut(strand_id)?;
        let (list, index) = resolve_body_mut(&mut strand.instructions, path)?;
        list.get_mut(index)
    }

    /// A header block must be first in its strand: nothing above or in front
    /// of one, and never nested inside another block's body.
    pub fn check_header_placement(
        &self,
        strand_id: &str,
        path: &[PathStep],
        instruction: &Instruction<K>,
    ) -> Result<(), String> {
        let Some(strand) = self.strand(strand_id) else {
            return Ok(());
        };
        let Some((list, index)) = resolve_body(&strand.instructions, path) else {
            return Ok(());
        };
        let label = K::HEADER_LABEL;
        if index == 0 && list.first().is_some_and(Instruction::is_header) {
            return Err(format!("Can't attach a block above a {label} block"));
        }
        if instruction.is_header() && (path.len() != 1 || index != 0) {
            return Err(format!(
                "A {label} block can only be the first block in a strand"
            ));
        }
        Ok(())
    }

    /// Inserts `instruction` at `path`. `Ok(false)` means the path doesn't
    /// resolve and nothing happened; a rejected placement is an `Err`.
    pub fn insert_instruction(
        &mut self,
        strand_id: &str,
        path: &[PathStep],
        instruction: Instruction<K>,
    ) -> Result<bool, String> {
        self.check_header_placement(strand_id, path, &instruction)?;
        let Some(strand) = self.strand_mut(strand_id) else {
            return Ok(false);
        };
        let Some((list, index)) = resolve_body_mut(&mut strand.instructions, path) else {
            return Ok(false);
        };
        let index = index.min(list.len());
        list.insert(index, instruction);
        Ok(true)
    }

    /// Overwrites the instruction at `path` in place - how an in-row edit (a
    /// changed dropdown, a captured key) is applied.
    pub fn replace_instruction(
        &mut self,
        strand_id: &str,
        path: &[PathStep],
        instruction: Instruction<K>,
    ) -> bool {
        let Some(strand) = self.strand_mut(strand_id) else {
            return false;
        };
        let Some((list, index)) = resolve_body_mut(&mut strand.instructions, path) else {
            return false;
        };
        if index >= list.len() {
            return false;
        }
        list[index] = instruction;
        true
    }

    /// Removes the instruction at `path`, leaving everything below it where
    /// it is.
    pub fn remove_instruction(&mut self, strand_id: &str, path: &[PathStep]) -> bool {
        let Some(strand) = self.strand_mut(strand_id) else {
            return false;
        };
        let Some((list, index)) = resolve_body_mut(&mut strand.instructions, path) else {
            return false;
        };
        if index >= list.len() {
            return false;
        }
        list.remove(index);
        self.prune_orphaned_comments();
        true
    }

    /// Deletes the instruction at `path`, splitting anything below it into a
    /// new strand at `(x, y)`. A strand left empty is dropped, not kept.
    pub fn delete_instruction(
        &mut self,
        strand_id: &str,
        path: &[PathStep],
        x: i32,
        y: i32,
    ) -> Result<Option<String>, String> {
        let strand = self.strand_mut(strand_id).ok_or("Unknown strand")?;
        let (list, index) =
            resolve_body_mut(&mut strand.instructions, path).ok_or("Unknown instruction path")?;
        if index >= list.len() {
            return Err("Instruction index out of range".to_string());
        }
        list.remove(index);
        let tail = list.split_off(index.min(list.len()));
        let strand_now_empty = strand.instructions.is_empty();
        let new_id = (!tail.is_empty()).then(|| {
            let strand = Strand::with_instructions(x, y, tail);
            let id = strand.id.clone();
            self.strands.push(strand);
            id
        });
        if strand_now_empty {
            self.strands.retain(|s| s.id != strand_id);
        }
        self.prune_orphaned_comments();
        Ok(new_id)
    }

    /// Moves the instruction at `path` up (`direction < 0`) or down one
    /// place, refusing a swap that would displace a strand's header block.
    pub fn reorder_instruction(
        &mut self,
        strand_id: &str,
        path: &[PathStep],
        direction: i32,
    ) -> bool {
        let Some(strand) = self.strand_mut(strand_id) else {
            return false;
        };
        let Some((list, index)) = resolve_body_mut(&mut strand.instructions, path) else {
            return false;
        };
        let len = list.len();
        if len <= 1 || index >= len {
            return false;
        }
        let new_index = if direction < 0 {
            index.saturating_sub(1)
        } else {
            (index + 1).min(len - 1)
        };
        if new_index == index {
            return false;
        }
        let touches_head_slot = path.len() == 1
            && (index == 0 || new_index == 0)
            && list.first().is_some_and(Instruction::is_header);
        if touches_head_slot {
            return false;
        }
        list.swap(index, new_index);
        true
    }

    /// Wipes every strand - "start this document over from scratch".
    pub fn clear_strands(&mut self) {
        self.strands.clear();
        self.prune_orphaned_comments();
    }

    // ── Strands ────────────────────────────────────────────────────────────

    /// Default spawn position for a newly created/detached strand, offset
    /// from the farthest-right one.
    pub fn next_strand_position(&self) -> (i32, i32) {
        let max_x = self.strands.iter().map(|s| s.x).max().unwrap_or(0);
        (max_x + NEW_STRAND_GAP, 0)
    }

    /// Creates a detached strand at `(x, y)` holding `instructions`
    /// verbatim, returning its id.
    pub fn add_strand(&mut self, x: i32, y: i32, instructions: Vec<Instruction<K>>) -> String {
        let strand = Strand::with_instructions(x, y, instructions);
        let id = strand.id.clone();
        self.strands.push(strand);
        id
    }

    /// Deletes a whole strand and everything on it.
    pub fn remove_strand(&mut self, strand_id: &str) -> bool {
        let before = self.strands.len();
        self.strands.retain(|strand| strand.id != strand_id);
        let removed = self.strands.len() != before;
        if removed {
            self.prune_orphaned_comments();
        }
        removed
    }

    /// Repositions a strand on the canvas - used while dragging a stack that
    /// ends up dropped on empty space rather than snapped onto another strand.
    pub fn move_strand(&mut self, strand_id: &str, x: i32, y: i32) -> bool {
        match self.strand_mut(strand_id) {
            Some(strand) => {
                strand.x = x;
                strand.y = y;
                true
            }
            None => false,
        }
    }

    /// Detaches the instructions at and after `path` into a new strand at
    /// `(x, y)` - how the frontend picks a block up before dropping it.
    pub fn split_strand(
        &mut self,
        strand_id: &str,
        path: &[PathStep],
        x: i32,
        y: i32,
    ) -> Result<String, String> {
        let strand = self.strand_mut(strand_id).ok_or("Unknown strand")?;
        let (list, index) =
            resolve_body_mut(&mut strand.instructions, path).ok_or("Unknown instruction path")?;
        if index >= list.len() {
            return Err("Split index out of range".to_string());
        }
        let tail = list.split_off(index);
        Ok(self.add_strand(x, y, tail))
    }

    /// Splices `dragged_id`'s instructions into `target_id` at `path` and
    /// drops the emptied strand. A strand with a header can't be dragged.
    pub fn merge_strand(
        &mut self,
        dragged_id: &str,
        target_id: &str,
        path: &[PathStep],
    ) -> Result<(), String> {
        let label = K::HEADER_LABEL;
        if dragged_id == target_id {
            return Err("Can't merge a strand into itself".to_string());
        }
        let dragged = self.strand(dragged_id).ok_or("Unknown dragged strand")?;
        if dragged.starts_with_header() {
            return Err(format!(
                "A strand headed by a {label} block can't be merged into another strand"
            ));
        }
        if let Some(target) = self.strand(target_id)
            && let Some((list, index)) = resolve_body(&target.instructions, path)
            && path.len() == 1
            && index == 0
            && list.first().is_some_and(Instruction::is_header)
        {
            return Err(format!("Can't attach a strand above a {label} block"));
        }
        let dragged_pos = self
            .strands
            .iter()
            .position(|s| s.id == dragged_id)
            .ok_or("Unknown dragged strand")?;
        let dragged = self.strands.remove(dragged_pos);
        // Target vanished (e.g. a concurrent edit) - put the dragged strand
        // back rather than silently dropping its instructions.
        let Some(target) = self.strand_mut(target_id) else {
            self.strands.push(dragged);
            return Err("Unknown target strand".to_string());
        };
        let Some((list, index)) = resolve_body_mut(&mut target.instructions, path) else {
            self.strands.push(dragged);
            return Err("Unknown target instruction path".to_string());
        };
        let index = index.min(list.len());
        list.splice(index..index, dragged.instructions);
        Ok(())
    }

    /// Moves the tail at and after `source_path` (same body list) into
    /// `target_id` at `target_path` in one atomic step - the Qt canvas's
    /// "attach on drop" without a split-then-merge round trip. Unlike
    /// [`BlockGraph::merge_strand`] the dragged tail stays part of its strand
    /// until the move, so `source_id == target_id` is allowed (same-strand
    /// reorder); an insertion index past the shortened list clamps to the end.
    pub fn merge_tail(
        &mut self,
        source_id: &str,
        source_path: &[PathStep],
        target_id: &str,
        target_path: &[PathStep],
    ) -> Result<(), String> {
        let label = K::HEADER_LABEL;
        // Read-only validation first so a rejected drop leaves everything
        // untouched (mirrors merge_strand's validate-before-move).
        let source = self.strand(source_id).ok_or("Unknown source strand")?;
        let (source_list_len, _source_index, tail_first_is_header) = {
            let Some((list, index)) = resolve_body(&source.instructions, source_path) else {
                return Err("Unknown source instruction path".to_string());
            };
            if index >= list.len() {
                return Err("Source index out of range".to_string());
            }
            (list.len(), index, list[index].is_header())
        };
        if tail_first_is_header {
            return Err(format!(
                "A {label} block can only be the first block in a strand"
            ));
        }
        let target = self.strand(target_id).ok_or("Unknown target strand")?;
        {
            let Some((list, index)) = resolve_body(&target.instructions, target_path) else {
                return Err("Unknown target instruction path".to_string());
            };
            // Same rule as merge_strand: nothing may land above a header.
            if target_path.len() == 1
                && index == 0
                && list.first().is_some_and(Instruction::is_header)
            {
                return Err(format!("Can't attach a block above a {label} block"));
            }
            // A no-op drop back exactly where the tail already starts is fine
            // (restores the list); anything deeper inside the dragged tail
            // itself would vanish with it, so reject it explicitly instead of
            // resolving to a dangling path after removal.
            if source_id == target_id
                && Self::path_contains(source_path, target_path, source_list_len)
            {
                return Err("Can't attach a block inside itself".to_string());
            }
        }
        // Mutate: extract the tail, then insert it. On target failure put the
        // tail back where it came from rather than dropping instructions.
        let tail = {
            let source_strand = self.strand_mut(source_id).ok_or("Unknown source strand")?;
            let (list, index) =
                resolve_body_mut(&mut source_strand.instructions, source_path)
                    .ok_or("Unknown source instruction path")?;
            if index >= list.len() {
                return Err("Source index out of range".to_string());
            }
            list.split_off(index)
        };
        let Some(target_strand) = self.strand_mut(target_id) else {
            // Target vanished between validation and mutation - restore.
            if let Some(source_strand) = self.strand_mut(source_id)
                && let Some((list, index)) =
                    resolve_body_mut(&mut source_strand.instructions, source_path)
            {
                let index = index.min(list.len());
                list.splice(index..index, tail);
            }
            return Err("Unknown target strand".to_string());
        };
        let Some((list, index)) = resolve_body_mut(&mut target_strand.instructions, target_path)
        else {
            if let Some(source_strand) = self.strand_mut(source_id)
                && let Some((list, index)) =
                    resolve_body_mut(&mut source_strand.instructions, source_path)
            {
                let index = index.min(list.len());
                list.splice(index..index, tail);
            }
            return Err("Unknown target instruction path".to_string());
        };
        let index = index.min(list.len());
        list.splice(index..index, tail);
        Ok(())
    }

    /// Whether `target` (an insertion path) lies strictly inside the tail
    /// starting at `source` (an instruction address) in the same strand:
    /// same parent list with an index past the tail start, or nested deeper
    /// inside any dragged block. `source_len` is the parent list's length
    /// before removal.
    fn path_contains(source: &[PathStep], target: &[PathStep], source_len: usize) -> bool {
        if target.len() < source.len() {
            return false;
        }
        // Parent steps must match (index and slot).
        for (i, step) in source.iter().enumerate() {
            if i == source.len() - 1 {
                break;
            }
            let other = &target[i];
            if step.index != other.index || step.slot != other.slot {
                return false;
            }
        }
        let last_source = &source[source.len() - 1];
        let at_depth = &target[source.len() - 1];
        if at_depth.index < last_source.index {
            return false;
        }
        if target.len() == source.len() {
            // Same list: insertion strictly inside the tail (past its start).
            // Equality (index == source start) is the no-op restore, allowed.
            return at_depth.index > last_source.index && at_depth.index < source_len;
        }
        // Deeper: the target descends into a block at an index the tail will
        // remove (at or past the tail start). Insertion exactly at the tail
        // start's own slot with index 0 would address the dragged block
        // itself, still inside - reject.
        at_depth.index >= last_source.index
    }

    // ── Values ─────────────────────────────────────────────────────────────

    /// Resolves a [`ValueLocation`] to the specific value node it addresses.
    pub fn value_at_mut(&mut self, location: &ValueLocation) -> Option<&mut Value> {
        match location {
            ValueLocation::Field {
                strand_id,
                index,
                field_id,
                path,
            } => {
                let strand = self.strand_mut(strand_id)?;
                let (list, instruction_index) = resolve_body_mut(&mut strand.instructions, index)?;
                let instruction = list.get_mut(instruction_index)?;
                instruction.kind.value_slot_mut(field_id)?.get_mut(path)
            }
            ValueLocation::Floating { floating_id, path } => {
                self.floating_value_mut(floating_id)?.value.get_mut(path)
            }
        }
    }

    /// The blank a top-level field restores to when nothing was shadowed.
    /// Nested positions and parked value blocks restore to a plain zero.
    pub fn blank_value_at(&self, location: &ValueLocation) -> Value {
        let ValueLocation::Field {
            strand_id,
            index,
            field_id,
            path,
        } = location
        else {
            return Value::number(0.0);
        };
        if !path.is_empty() {
            return Value::number(0.0);
        }
        self.instruction_at(strand_id, index)
            .and_then(|ins| ins.kind.blank_field_value(field_id, &self.block_defs))
            .unwrap_or_else(|| Value::number(0.0))
    }

    /// Whether the addressed field only accepts whole numbers.
    pub fn location_requires_integer(&self, location: &ValueLocation) -> bool {
        let ValueLocation::Field {
            strand_id,
            index,
            field_id,
            ..
        } = location
        else {
            return false;
        };
        self.instruction_at(strand_id, index)
            .is_some_and(|ins| ins.kind.field_requires_integer(field_id))
    }

    /// Writes typed text into the addressed slot, verbatim for a text slot
    /// and parsed for a numeric one. See [`ValueEdit`].
    pub fn edit_value_text(&mut self, location: &ValueLocation, text: String) -> ValueEdit {
        let requires_integer = self.location_requires_integer(location);
        let Some(node) = self.value_at_mut(location) else {
            return ValueEdit::Missing;
        };
        if matches!(node, Value::Text { .. }) {
            *node = Value::Text { value: text };
            return ValueEdit::Text;
        }
        let parsed = if requires_integer {
            text.trim().parse::<i32>().map(f64::from).ok()
        } else {
            text.trim().parse::<f64>().ok()
        };
        match parsed {
            Some(value) => {
                *node = Value::number(value);
                ValueEdit::Number { parsed: true }
            }
            None => ValueEdit::Number { parsed: false },
        }
    }

    /// Rebuilds the addressed node as `kind` (a palette entry, `"Number"`,
    /// `"Text"` or `"Var:<name>"`) - see [`apply_value_kind`].
    pub fn set_value_kind(
        &mut self,
        location: &ValueLocation,
        kind: &str,
        env: &HashMap<String, Evaluated>,
    ) -> Result<(), String> {
        match self.value_at_mut(location) {
            Some(node) => apply_value_kind(node, kind, env),
            None => Ok(()),
        }
    }

    /// Removes the value at `location`, leaving whatever it shadowed (or the
    /// field's blank); a parked block addressed at its root is deleted.
    pub fn take_value(&mut self, location: &ValueLocation) -> Option<Value> {
        if let ValueLocation::Floating { floating_id, path } = location
            && path.is_empty()
        {
            let index = self
                .floating_values
                .iter()
                .position(|f| &f.id == floating_id)?;
            return Some(self.floating_values.remove(index).value);
        }
        let fallback = self.blank_value_at(location);
        let node = self.value_at_mut(location)?;
        let restored = node.saved().cloned().unwrap_or(fallback);
        Some(std::mem::replace(node, restored))
    }

    /// Overwrites the node at `location`, tucking what was there into the
    /// incoming operator's `saved` so dragging it back out restores it.
    pub fn put_value(&mut self, location: &ValueLocation, mut value: Value) -> bool {
        let Some(node) = self.value_at_mut(location) else {
            return false;
        };
        if let Value::Op { saved, .. } | Value::Call { saved, .. } = &mut value {
            **saved = node.clone();
        }
        *node = value;
        true
    }

    // ── Parked value blocks ────────────────────────────────────────────────

    /// Creates a value block parked on open canvas - for a palette drop, or
    /// the "create" half of dragging an existing block out onto canvas.
    pub fn add_floating_value(
        &mut self,
        x: i32,
        y: i32,
        value: Value,
        origin_block_id: Option<String>,
    ) -> String {
        let floating = FloatingValue::new(x, y, value, origin_block_id);
        let id = floating.id.clone();
        self.floating_values.push(floating);
        id
    }

    pub fn move_floating_value(&mut self, floating_id: &str, x: i32, y: i32) -> bool {
        match self.floating_value_mut(floating_id) {
            Some(floating) => {
                floating.x = x;
                floating.y = y;
                true
            }
            None => false,
        }
    }

    pub fn remove_floating_value(&mut self, floating_id: &str) -> bool {
        let before = self.floating_values.len();
        self.floating_values.retain(|f| f.id != floating_id);
        self.floating_values.len() != before
    }

    // ── Notes ──────────────────────────────────────────────────────────────

    /// Creates a note, freestanding or pinned to an instruction - `(x, y)` is
    /// an offset from that instruction's own position (see [`Comment`]).
    pub fn add_comment(
        &mut self,
        x: i32,
        y: i32,
        text: String,
        attached_to: Option<String>,
    ) -> String {
        let comment = Comment::new(x, y, text, attached_to);
        let id = comment.id.clone();
        self.comments.push(comment);
        id
    }

    pub fn move_comment(&mut self, comment_id: &str, x: i32, y: i32) -> bool {
        match self.comment_mut(comment_id) {
            Some(comment) => {
                comment.x = x;
                comment.y = y;
                true
            }
            None => false,
        }
    }

    pub fn set_comment_text(&mut self, comment_id: &str, text: String) -> bool {
        match self.comment_mut(comment_id) {
            Some(comment) => {
                comment.text = text;
                true
            }
            None => false,
        }
    }

    pub fn set_comment_collapsed(&mut self, comment_id: &str, collapsed: bool) -> bool {
        match self.comment_mut(comment_id) {
            Some(comment) => {
                comment.collapsed = collapsed;
                true
            }
            None => false,
        }
    }

    pub fn remove_comment(&mut self, comment_id: &str) -> bool {
        let before = self.comments.len();
        self.comments.retain(|c| c.id != comment_id);
        self.comments.len() != before
    }

    // ── Custom blocks ──────────────────────────────────────────────────────

    /// Updates a block's prototype, reconciling call-site `args` to the new
    /// input list and renaming body params that only changed name.
    pub fn update_block(
        &mut self,
        block_id: &str,
        new_pieces: Vec<BlockPiece>,
        shape: BlockShape,
        color: &str,
    ) -> Result<(), String> {
        BlockDef::validate_pieces(&new_pieces)?;
        let color = normalize_block_color(color).ok_or("Choose a valid block color")?;
        let old_pieces = self
            .block_def(block_id)
            .map(|def| def.pieces.clone())
            .ok_or("Unknown block")?;

        for (old_name, new_name) in input_renames(&old_pieces, &new_pieces) {
            self.rename_block_input_body(block_id, &old_name, &new_name);
        }
        self.reconcile_block_call_args(block_id, &old_pieces, &new_pieces);

        let def = self.block_def_mut(block_id).ok_or("Unknown block")?;
        def.pieces = new_pieces;
        def.shape = shape;
        def.color = color;
        Ok(())
    }
}

/// Inputs that kept their piece id but changed name, as `(old, new)` - the
/// renames a block's own body has to follow.
fn input_renames(old_pieces: &[BlockPiece], new_pieces: &[BlockPiece]) -> Vec<(String, String)> {
    new_pieces
        .iter()
        .filter_map(|new_piece| {
            let BlockPiece::Input {
                id, name: new_name, ..
            } = new_piece
            else {
                return None;
            };
            let old_name = old_pieces.iter().find_map(|piece| match piece {
                BlockPiece::Input {
                    id: old_id, name, ..
                } if old_id == id => Some(name),
                _ => None,
            })?;
            (old_name != new_name).then(|| (old_name.clone(), new_name.clone()))
        })
        .collect()
}

/// Rebuilds `node` as `kind` in place, keeping what it can: `(2)+(3)`
/// collapses to `5`, and a swapped operator keeps the operands that fit.
pub fn apply_value_kind(
    node: &mut Value,
    kind: &str,
    env: &HashMap<String, Evaluated>,
) -> Result<(), String> {
    match kind {
        "Number" => {
            let n = node
                .resolve_vars(env)
                .eval()
                .and_then(|e| e.as_number())
                .unwrap_or(0.0);
            *node = Value::number(n);
        }
        "Text" => {
            let text = node
                .resolve_vars(env)
                .eval()
                .map(|e| e.as_text())
                .unwrap_or_default();
            *node = Value::Text { value: text };
        }
        _ if kind.starts_with("Var:") => {
            // A variable reporter is a plain leaf - restores to `0` on take-out.
            let name = kind["Var:".len()..].to_string();
            *node = Value::Var { name };
        }
        _ => {
            // Any other kind is an operator. Swapping one resizes `args` to
            // the new arity; a leaf is tucked into `saved` so it can come back.
            let spec = operator_kind(kind).ok_or_else(|| format!("Unknown value kind: {kind}"))?;
            let existing = std::mem::replace(node, Value::number(0.0));
            *node = match existing {
                Value::Op {
                    mut args, saved, ..
                } => {
                    let mut defaults = (spec.default_args)();
                    if args.len() < spec.arity {
                        args.extend(defaults.split_off(args.len()));
                    } else {
                        args.truncate(spec.arity);
                    }
                    Value::Op {
                        op: spec.op,
                        args,
                        saved,
                    }
                }
                other => Value::Op {
                    op: spec.op,
                    args: (spec.default_args)(),
                    saved: Box::new(other),
                },
            };
        }
    }
    Ok(())
}
