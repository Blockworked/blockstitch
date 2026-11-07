# Working on blockstitch

blockstitch is the block editor shared by Blockwork, Blockloom and the
website. The README has the layout; `docs/hosting.md` is how a host uses it.

## Build and test

```bash
just test-core   # Rust: crates/blockstitch-core and crates/blockstitch-ffi (no Qt)
just test-qml    # QML: tests/qml (needs Qt 6.10 or newer's qmltestrunner on PATH; CI uses 6.12.0)
just build       # the QML crate (needs qmake6, or QMAKE set)
just fmt         # rustfmt, as CI checks it
```

## Where a change goes

- **Something every host needs** (a document edit, a value operator, undo,
  placement rules): `crates/blockstitch-core`, with a test under its
  `tests/`. Hosts reach their own instruction enum through the `BlockKind`
  trait (`graph/instruction.rs`); a new trait method needs a default so
  existing hosts still compile.
- **A new piece kind or row feature**: `BlockRegistry.qml` lists every piece
  kind in the comment above its `rows` property. `InstructionBlock.qml` draws
  pieces, `PalettePanel.qml` the palette copies. Describe it in
  `qml/README.md` and add a QML test (`tests/qml/tst_*.qml`; `testRows.js`
  holds shared fixture rows).
- **A new QML file**: list it in `qml/module.json`, or both builds fail.
- **Anything host-specific**: keep it in the host and turn it on from there
  (see "What a neutral host gets" in `qml/README.md`).

## Hosts

Blockwork and Blockloom pin one blockstitch commit. After a change lands,
each host moves its pin (Blockwork: `node scripts/set-blockstitch-rev.js
<sha>`) and runs its own tests. How pins move is under "Pins" in
`docs/hosting.md`; a change a host must act on goes under "Migration notes"
there.

## Rules

- Keep comments short and plain. No em-dashes.
- License: GPL-3.0-or-later (`LICENSE`).
