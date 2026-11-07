import QtQuick
import QtTest
import com.blockworked.Blockstitch 1.0

Item {
    id: scene
    width: 1000
    height: 760

    Component { id: editorFactory; BlockDefinitionEditor { anchors.fill: parent } }

    TestCase {
        name: "BlockDefinitionSelection"
        when: windowShown

        function test_canvas_click_commits_and_deselects() {
            const editor = createTemporaryObject(editorFactory, scene);
            editor.load({pieces: [
                {kind: "Label", text: "example"},
                {kind: "Input", name: "value", value_type: "Any"}
            ]});
            const viewport = findChild(editor, "definitionPreviewViewport");
            waitForRendering(viewport);
            const label = editor.findPiece(editor, 0);
            mouseClick(label);
            tryCompare(editor, "editingPiece", 0);
            tryVerify(() => editor.activeEditor && editor.activeEditor.activeFocus);
            editor.activeEditor.text = "renamed";

            mouseClick(viewport, 20, 20);
            compare(editor.selectedPiece, -1);
            compare(editor.editingPiece, -1);
            compare(editor.activeEditor, null);
            compare(editor.resultPieces()[0].text, "renamed");
            verify(!label.selected);

            const input = editor.findPiece(editor, 1);
            mouseClick(input);
            tryCompare(editor, "editingPiece", 1);
            compare(editor.selectedPiece, 1);
            tryVerify(() => editor.activeEditor && editor.activeEditor.activeFocus);
        }
    }
}
