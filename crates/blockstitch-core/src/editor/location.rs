//! Addressing a single [`crate::value::Value`] node, and the raw-text
//! buffers that go with the ones being typed into.

use crate::editor::path::InstrPath;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;

/// Addresses one value node: an instruction's field or a parked value
/// block, then `path` within it (`n` steps into `args[n]` at each operator).
/// `field_id` is opaque here - only the frontend and the host's
/// [`crate::graph::BlockKind::value_slot_mut`] read it. Also the wire shape.
#[derive(Debug, Clone, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(tag = "kind")]
pub enum ValueLocation {
    Field {
        strand_id: String,
        index: InstrPath,
        field_id: String,
        path: Vec<u8>,
    },
    Floating {
        floating_id: String,
        path: Vec<u8>,
    },
}

impl ValueLocation {
    /// Path within the addressed root value tree.
    pub fn path(&self) -> &[u8] {
        match self {
            ValueLocation::Field { path, .. } | ValueLocation::Floating { path, .. } => path,
        }
    }

    /// True if both address a node in the same tree, ignoring `path` - for
    /// pruning stale text buffers when a subtree is replaced.
    pub fn same_root(&self, other: &ValueLocation) -> bool {
        match (self, other) {
            (
                ValueLocation::Field {
                    strand_id: s1,
                    index: i1,
                    field_id: f1,
                    ..
                },
                ValueLocation::Field {
                    strand_id: s2,
                    index: i2,
                    field_id: f2,
                    ..
                },
            ) => s1 == s2 && i1 == i2 && f1 == f2,
            (
                ValueLocation::Floating { floating_id: a, .. },
                ValueLocation::Floating { floating_id: b, .. },
            ) => a == b,
            _ => false,
        }
    }

    /// `Some(strand_id)` for a `Field` location, `None` for `Floating` -
    /// used to prune buffered entries when a whole strand is removed.
    pub fn strand_id(&self) -> Option<&str> {
        match self {
            ValueLocation::Field { strand_id, .. } => Some(strand_id),
            ValueLocation::Floating { .. } => None,
        }
    }
}

/// Raw text typed into a slot that can't hold it yet (a half-written number
/// like `"-"`), so the field doesn't snap back mid-edit.
pub type ValueBuffers = HashMap<ValueLocation, String>;

/// Drops buffered entries at or beneath `location` - used after a subtree is
/// replaced wholesale, so stale text doesn't linger against the wrong node.
pub fn prune_value_buffers(buffers: &mut ValueBuffers, location: &ValueLocation) {
    let path = location.path();
    buffers.retain(|loc, _| !(loc.same_root(location) && loc.path().starts_with(path)));
}

/// Drops every buffered entry belonging to `strand_id` - for when a whole
/// strand goes away.
pub fn drop_strand_buffers(buffers: &mut ValueBuffers, strand_id: &str) {
    buffers.retain(|loc, _| loc.strand_id() != Some(strand_id));
}

/// Drops buffered entries whose strand no longer exists.
pub fn retain_live_buffers(buffers: &mut ValueBuffers, live_strand_ids: &[String]) {
    buffers.retain(|loc, _| {
        loc.strand_id()
            .is_none_or(|id| live_strand_ids.iter().any(|live| live == id))
    });
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::editor::path::PathStep;

    /// The exact payload blockstitch's own `fieldLocation()` sends.
    #[test]
    fn field_location_matches_the_frontend_shape() {
        let json = r#"{"kind":"Field","strand_id":"s1","index":[{"index":2,"slot":null}],"field_id":"WaitDuration","path":[0,1]}"#;
        let location: ValueLocation = serde_json::from_str(json).unwrap();
        assert_eq!(
            location,
            ValueLocation::Field {
                strand_id: "s1".to_string(),
                index: vec![PathStep::at(2)],
                field_id: "WaitDuration".to_string(),
                path: vec![0, 1],
            }
        );
        assert_eq!(serde_json::to_string(&location).unwrap(), json);
    }

    #[test]
    fn floating_location_matches_the_frontend_shape() {
        let json = r#"{"kind":"Floating","floating_id":"f1","path":[]}"#;
        let location: ValueLocation = serde_json::from_str(json).unwrap();
        assert_eq!(location.strand_id(), None);
        assert_eq!(serde_json::to_string(&location).unwrap(), json);
    }

    #[test]
    fn pruning_drops_the_subtree_but_keeps_siblings_and_other_roots() {
        let field = |strand: &str, path: Vec<u8>| ValueLocation::Field {
            strand_id: strand.to_string(),
            index: vec![PathStep::at(1)],
            field_id: "WaitDuration".to_string(),
            path,
        };
        let mut buffers = ValueBuffers::new();
        buffers.insert(field("s1", vec![0]), "sibling".to_string());
        buffers.insert(field("s1", vec![1]), "descendant".to_string());
        buffers.insert(field("s1", vec![1, 0]), "nested descendant".to_string());
        buffers.insert(field("s2", vec![1]), "other strand".to_string());

        prune_value_buffers(&mut buffers, &field("s1", vec![1]));
        assert_eq!(buffers.len(), 2);
        assert!(buffers.contains_key(&field("s1", vec![0])));
        assert!(buffers.contains_key(&field("s2", vec![1])));

        drop_strand_buffers(&mut buffers, "s1");
        assert_eq!(buffers.len(), 1);
        retain_live_buffers(&mut buffers, &["s3".to_string()]);
        assert!(buffers.is_empty());
    }
}
