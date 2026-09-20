//! Undo/redo over whole-document snapshots, and the edit-coalescing key
//! that keeps a run of keystrokes from becoming a run of undo steps.

use crate::editor::location::ValueLocation;
use crate::editor::path::InstrPath;

/// What the user is currently typing into, so a run of keystrokes there
/// coalesces into one undo step - see [`History::push_for_session`].
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum EditSession {
    Value(ValueLocation),
    Instruction { strand_id: String, index: InstrPath },
    Comment { comment_id: String },
}

/// A bounded undo/redo stack over snapshots of `S` - in practice a cloned
/// [`crate::graph::BlockGraph`], the whole of what an edit can change.
#[derive(Debug, Clone)]
pub struct History<S> {
    undo: Vec<S>,
    redo: Vec<S>,
    limit: usize,
    session: Option<EditSession>,
}

impl<S> History<S> {
    /// `limit` is the number of undo steps kept; the oldest is dropped past
    /// that.
    pub fn new(limit: usize) -> Self {
        Self {
            undo: Vec::new(),
            redo: Vec::new(),
            limit,
            session: None,
        }
    }

    /// Checkpoints `snapshot`, drops the redo branch, and ends the current
    /// edit session.
    pub fn push(&mut self, snapshot: S) {
        self.session = None;
        if self.limit == 0 {
            return;
        }
        if self.undo.len() >= self.limit {
            self.undo.remove(0);
        }
        self.undo.push(snapshot);
        self.redo.clear();
    }

    /// Checkpoints only if `session` isn't the one already in progress.
    /// Returns whether it did.
    pub fn push_for_session(&mut self, snapshot: S, session: EditSession) -> bool {
        let is_new = self.session.as_ref() != Some(&session);
        if is_new {
            self.push(snapshot);
        }
        self.session = Some(session);
        is_new
    }

    /// Hands back the previous snapshot, taking `current` onto the redo
    /// branch. `None` (and `current` dropped) when there's nothing to undo.
    pub fn undo(&mut self, current: S) -> Option<S> {
        let previous = self.undo.pop()?;
        self.redo.push(current);
        self.session = None;
        Some(previous)
    }

    /// Mirror of [`History::undo`].
    pub fn redo(&mut self, current: S) -> Option<S> {
        let next = self.redo.pop()?;
        self.undo.push(current);
        self.session = None;
        Some(next)
    }

    pub fn can_undo(&self) -> bool {
        !self.undo.is_empty()
    }

    pub fn can_redo(&self) -> bool {
        !self.redo.is_empty()
    }

    /// Forgets both branches - for when the document is replaced outright.
    pub fn clear(&mut self) {
        self.undo.clear();
        self.redo.clear();
        self.session = None;
    }

    /// Ends the current edit session without checkpointing.
    pub fn end_session(&mut self) {
        self.session = None;
    }

    pub fn session(&self) -> Option<&EditSession> {
        self.session.as_ref()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn undo_and_redo_walk_the_stack() {
        let mut history = History::new(8);
        history.push("a");
        history.push("b");
        assert!(history.can_undo());
        assert_eq!(history.undo("c"), Some("b"));
        assert_eq!(history.undo("b"), Some("a"));
        assert_eq!(history.undo("a"), None);
        assert_eq!(history.redo("a"), Some("b"));
    }

    #[test]
    fn push_drops_the_redo_branch() {
        let mut history = History::new(8);
        history.push("a");
        assert_eq!(history.undo("b"), Some("a"));
        assert!(history.can_redo());
        history.push("a");
        assert!(!history.can_redo());
    }

    #[test]
    fn limit_drops_the_oldest_step() {
        let mut history = History::new(2);
        history.push("a");
        history.push("b");
        history.push("c");
        assert_eq!(history.undo("d"), Some("c"));
        assert_eq!(history.undo("c"), Some("b"));
        assert_eq!(history.undo("b"), None);
    }

    #[test]
    fn a_continuing_session_does_not_checkpoint_again() {
        let mut history = History::new(8);
        let session = || EditSession::Comment {
            comment_id: "c1".to_string(),
        };
        assert!(history.push_for_session("a", session()));
        assert!(!history.push_for_session("b", session()));
        assert!(history.push_for_session(
            "c",
            EditSession::Comment {
                comment_id: "c2".to_string()
            }
        ));
    }
}
