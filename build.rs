use cxx_qt_build::{CxxQtBuilder, QmlFile, QmlModule};

fn main() {
    CxxQtBuilder::new_qml_module(
        QmlModule::new("com.blockworked.Blockstitch")
            .version(1, 0)
            .qml_file(QmlFile::from("qml/Blockstitch/Theme.qml").singleton(true))
            .qml_files([
                "qml/Blockstitch/LucideIcon.qml",
                "qml/Blockstitch/BlockSurface.qml",
                "qml/Blockstitch/BwButton.qml",
                "qml/Blockstitch/BwTextField.qml",
                "qml/Blockstitch/BwComboBox.qml",
                "qml/Blockstitch/BwCheckBox.qml",
                "qml/Blockstitch/BwMenuItem.qml",
                "qml/Blockstitch/BwSwitch.qml",
                "qml/Blockstitch/ValueChip.qml",
                "qml/Blockstitch/InstructionBlock.qml",
                "qml/Blockstitch/PalettePanel.qml",
                "qml/Blockstitch/BlockCanvas.qml",
            ]),
    )
    .qt_module("QuickControls2")
    .qt_module("QuickShapes")
    .build();
}
