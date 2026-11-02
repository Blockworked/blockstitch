import QtQuick
import QtTest
import com.blockworked.Blockstitch

Item {
    id: scene
    width: 700; height: 700
    PalettePanel {
        id: palette
        width: 360; height: 700
        instructionTypes: ["Wait", "SetClipboard", "SetVariable", "ChangeVariable", "Key"]
        listInstructionTypes: ["AddToList"]
        variables: ["score"]
        extraCategories: ({ SetClipboard: "system" })
    }
    TestCase {
        name: "PaletteSections"
        when: windowShown

        function names(section) { return section.items.map(i => i.name); }
        function sectionsOf(category) { return palette.resolvedSections.filter(s => s.category === category); }

        function test_variablesSitWithMakeAVariable() {
            palette.sections = [];
            const data = sectionsOf("data");
            compare(data[0].action, "makeVariable");
            compare(names(data[0]), ["@variables", "SetVariable", "ChangeVariable"]);
            compare(data[1].action, "makeList");
            verify(names(data[1]).indexOf("AddToList") > 0);
            verify(!palette.resolvedSections.some(s => s.action === "makeDict"));
            verify(names(sectionsOf("system")[0]).indexOf("SetClipboard") >= 0);
        }

        function test_hostSectionsOrderAndLeftovers() {
            palette.sections = [{ category: "input", title: "Keyboard", items: ["Key", "Missing"] },
                                { category: "control", title: "Waiting", items: ["Wait"] }];
            const ids = palette.resolvedSections.map(s => s.category);
            verify(ids.indexOf("input") < ids.indexOf("control"));
            compare(names(sectionsOf("input")[0]), ["Key"]);
            compare(sectionsOf("control")[0].title, "Waiting");
            // Built-in operators no section names land untitled at the end of Operators.
            const operators = sectionsOf("operators");
            compare(operators.length, 1);
            compare(operators[0].title, "");
            verify(names(operators[0]).indexOf("Add") >= 0);
            compare(palette.categoryCount("input"), 1);
            palette.sections = [];
        }

        function test_searchShowsOnlyMatches() {
            palette.searchText = "clipboard";
            verify(palette.itemMatches({ kind: "instruction", name: "SetClipboard" }));
            verify(!palette.itemMatches({ kind: "instruction", name: "Wait" }));
            verify(!palette.itemMatches({ kind: "variables" }));
            palette.searchText = "sco";
            verify(palette.itemMatches({ kind: "variables" }));
            palette.searchText = "";
        }
    }
}
