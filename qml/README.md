# Blockstitch QML frontend

This directory is the Qt 6 counterpart to the existing Vue frontend in
`src/`. It intentionally does not replace or modify the browser package.

The components are registered as the `com.blockworked.Blockstitch` QML module
by the `blockstitch-qml` crate. `BlockCanvas` renders draggable Scratch-style strands on a zoomable
dotted workspace, while `PalettePanel` and the small controls share the same
dark, beveled visual language as the browser UI.

Native consumers depend on the repository's root Cargo package and call
`blockstitch_qml::init()` before creating their QML engine. The existing npm
package and everything under `src/` remain the browser implementation.
