//! Native Qt/QML frontend components for Blockstitch.
//!
//! Native consumers call [`init`] before constructing their QML engine.

pub const QML_URI: &str = "com.blockworked.Blockstitch";

/// Register the statically linked Blockstitch QML module and its resources.
pub fn init() {
    cxx_qt::init_qml_module!("com.blockworked.Blockstitch");
}
