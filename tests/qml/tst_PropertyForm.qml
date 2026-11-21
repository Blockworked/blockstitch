import QtQuick
import QtTest
import com.blockworked.Blockstitch

// The schema-built property form: rows, conditions, clamps, nesting, enums.
Item {
    id: scene
    width: 420; height: 900

    TestCase {
        id: test
        name: "PropertyForm"
        when: windowShown

        readonly property var lightFields: [
            { name: "kind", type: "choice", options: ["Point", "Spot", "Rect"], default: "Point" },
            { name: "intensity", type: "number", min: 0, default: 800, ui: { unit: "lm" } },
            { name: "inner_angle", type: "number", default: 30, ui: { label: "Cone inner", visible_when: { field: "kind", equals: "Spot" } } },
            { name: "radius", type: "number", default: 0, ui: { visible_when: { field: "kind", one_of: ["Point", "Spot"] } } },
            { name: "shadows", type: "bool", default: false },
            { name: "bias", type: "optional", inner: { type: "number", min: 0 }, default: null,
              ui: { visible_when: { all: [{ field: "kind", not_one_of: ["Rect"] }, { field: "shadows" }] } } },
            { name: "beam", type: "struct", default: { density: 0, motes: { enabled: false, count: 160 } }, fields: [
                { name: "density", type: "number", default: 0, ui: { visible_when: { field: "/shadows" } } },
                { name: "motes", type: "struct", default: { enabled: false, count: 160 }, fields: [
                    { name: "enabled", type: "bool", default: false },
                    { name: "count", type: "int", min: 0, max: 4096, default: 160, ui: { visible_when: { field: "enabled" } } }
                ] }
            ] },
            { name: "shape", type: "enum", tag: "shape", default: { shape: "Point" }, variants: [
                { name: "Point" },
                { name: "Sphere", fields: [{ name: "radius", type: "number", default: 1 }] }
            ] },
            { name: "tags", type: "list", item: { type: "text" }, default: [] },
            { name: "secret", type: "number", default: 3, ui: { advanced: true } }
        ]

        Component {
            id: formComponent
            PropertyForm {
                id: form
                width: 400
                fields: test.lightFields
                property var last: null
                onChanged: next => { last = next; value = next; }
            }
        }
        SignalSpy { id: spy; signalName: "changed" }

        function make(value) {
            const form = createTemporaryObject(formComponent, scene, { value: value });
            verify(form);
            spy.target = form; spy.clear();
            return form;
        }
        function row(form, name) { return findChild(form, "property-row-" + name); }
        function field(form, name, objectName) { const r = row(form, name); return r ? findChild(r, objectName) : null; }

        function test_rowsFollowConditions() {
            const form = make({ kind: "Point" });
            tryVerify(() => row(form, "intensity") !== null);
            verify(row(form, "radius").visible, "one_of holds for Point");
            verify(!row(form, "inner_angle").visible, "equals Spot fails for Point");
            verify(!row(form, "bias").visible, "all needs shadows");
            form.value = { kind: "Spot", shadows: true };
            verify(row(form, "inner_angle").visible);
            verify(row(form, "bias").visible);
            form.value = { kind: "Rect", shadows: true };
            verify(!row(form, "radius").visible);
            verify(!row(form, "bias").visible, "not_one_of excludes Rect");
        }

        function test_aNumberClampsAndKeepsOtherKeys() {
            const form = make({ kind: "Point", unknown_key: 7 });
            const box = field(form, "intensity", "property-number");
            verify(box);
            compare(box.text, "800", "a missing value shows its default");
            box.text = "-5";
            box.editingFinished();
            compare(spy.count, 1);
            compare(form.last.intensity, 0, "min clamps");
            compare(form.last.unknown_key, 7, "keys the schema doesn't name are kept");
        }

        function test_nestedStructsAndTopConditions() {
            const form = make({ shadows: false });
            tryVerify(() => row(form, "beam") !== null);
            const beam = row(form, "beam");
            tryVerify(() => findChild(beam, "property-row-density") !== null);
            verify(!findChild(beam, "property-row-density").visible, "/shadows reads the top record");
            form.value = { shadows: true };
            verify(findChild(beam, "property-row-density").visible);
            const motes = findChild(beam, "property-row-motes");
            tryVerify(() => findChild(motes, "property-row-count") !== null);
            verify(!findChild(motes, "property-row-count").visible);
            findChild(findChild(motes, "property-row-enabled"), "property-switch").toggle();
            compare(form.last.beam.motes.enabled, true, "a nested edit reports the whole record");
            compare(form.last.beam.motes.count, 160, "and its siblings' defaults");
            compare(form.last.beam.density, 0);
        }

        function test_optionalSwitchesBetweenNullAndAValue() {
            const form = make({ kind: "Point", shadows: true });
            const toggle = field(form, "bias", "property-optional");
            verify(toggle);
            toggle.toggle();
            compare(form.last.bias, 0, "turning it on starts at the inner type's zero");
            tryVerify(() => field(form, "bias", "property-number") !== null);
            toggle.toggle();
            compare(form.last.bias, null);
        }

        function test_taggedEnumSwitchesVariant() {
            const form = make({});
            const pick = field(form, "shape", "property-variant");
            verify(pick);
            compare(pick.currentIndex, 0);
            pick.activated(1);
            compare(form.last.shape.shape, "Sphere");
            compare(form.last.shape.radius, 1, "the new variant's fields start at their defaults");
            tryVerify(() => findChild(row(form, "shape"), "property-row-radius") !== null);
        }

        function test_listsAddAndRemove() {
            const form = make({ tags: ["a"] });
            const add = field(form, "tags", "property-add");
            verify(add);
            add.clicked();
            compare(form.last.tags, ["a", ""]);
            const remove = field(form, "tags", "property-remove");
            remove.clicked();
            compare(form.last.tags.length, 1);
        }

        function test_advancedFieldsFoldAway() {
            const form = make({});
            const section = findChild(form, "property-section-Advanced");
            verify(section);
            compare(row(form, "secret"), null, "folded until opened");
        }

        Component {
            id: hostColor
            Item {
                objectName: "host-color"
                property var field
                property var value
                signal edited(var next)
            }
        }
        function test_hostEditorsWin() {
            const form = createTemporaryObject(formComponent, scene, {
                fields: [{ name: "tint", type: "color", default: "#FFFFFF" }],
                value: {}, editors: { color: hostColor } });
            tryVerify(() => findChild(form, "host-color") !== null);
            const editor = findChild(form, "host-color");
            compare(editor.value, "#FFFFFF");
            spy.target = form; spy.clear();
            editor.edited("#FF0000");
            compare(form.last.tint, "#FF0000");
        }
    }
}
