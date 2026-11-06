# blockstitch

The block editor shared by Blockwork, Blockloom and the website.

| Path | What it is |
| --- | --- |
| `crates/blockstitch-core` | Rust backend: document model, values, editing operations, undo |
| `crates/blockstitch-ffi`, `include/` | C boundary for the browser build |
| `qml/Blockstitch` | QML module `com.blockworked.Blockstitch`: canvas, palette, definition editor, theme |
| `qml/module.json` | The module's file list, read by `build.rs` and `cmake/BlockstitchQml.cmake` |
| `rust/lib.rs`, `build.rs` | The cxx-qt crate that statically links the QML module |
| `tests/qml` | QML tests (`QMLTESTRUNNER=qmltestrunner tests/qml/run.sh`) |
| `docs/hosting.md` | How a host app puts the editor on its own blocks |

Tests: `just test` (or `just test-core`, which needs no Qt, and `just test-qml`). CI runs both (`.github/workflows/checks.yml`).
The two crates under `crates/` are standalone workspaces with their own
lockfiles, so a plain `cargo test` at the root only builds the QML crate.

Hosts pin all three crates to one commit and move them together (see
"Pins" in `docs/hosting.md`).
