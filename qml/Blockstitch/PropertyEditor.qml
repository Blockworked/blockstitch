import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// Edits one value of a field schema: bool, int, number, text, color, vec3,
// choice, asset, actor, list, struct, map, optional, enum or opaque. It only
// asks: it shows `value` and reports `edited(next)`. A host editor in
// `editors` (by type) wins over the built-in one.
ColumnLayout {
    id: root
    property var field: ({ type: "text" })
    property var value: null
    property var record: null
    property var editors: ({})
    property var host: null
    property real labelWidth: 78
    signal edited(var next)
    spacing: 4

    readonly property string kind: field && field.type ? field.type : "text"
    readonly property string widget: field && field.ui && field.ui.widget ? field.ui.widget : ""
    readonly property string unit: field && field.ui && field.ui.unit ? field.ui.unit : ""
    readonly property var hostEditor: root.editors ? root.editors[root.kind] || null : null

    function present(v) { return v !== undefined && v !== null; }
    function clamp(n) {
        let v = n;
        if (present(field.min)) v = Math.max(field.min, v);
        if (present(field.max)) v = Math.min(field.max, v);
        return kind === "int" ? Math.round(v) : v;
    }
    // Seven significant digits: no f32 noise.
    function shown(v) {
        if (!present(v)) return "";
        const n = Number(v);
        return Number.isInteger(n) ? String(n) : String(Number(n.toPrecision(7)));
    }
    // QVariantList values fail Array.isArray; read either as a real array.
    function toArray(v) {
        if (Array.isArray(v)) return v;
        if (v !== null && typeof v === "object" && typeof v.length === "number") return Array.prototype.slice.call(v);
        return null;
    }
    // What a fresh value of type `t` starts as.
    function zeroOf(t) {
        if (!t) return null;
        switch (t.type) {
        case "bool": return false;
        case "int": case "number": return present(t.min) && t.min > 0 ? t.min : 0;
        case "color": return "#FFFFFF";
        case "vec3": return [0, 0, 0];
        case "choice": return t.options && t.options.length ? t.options[0] : "";
        case "list": return [];
        case "map": return ({});
        case "optional": return null;
        case "struct": {
            const out = {};
            for (const f of t.fields || []) out[f.name] = present(f.default) ? f.default : zeroOf(f);
            return out;
        }
        case "enum": return t.variants && t.variants.length ? variantValue(t, t.variants[0], null) : null;
        case "opaque": return null;
        default: return "";
        }
    }

    // Enums: serde's internal form `{tag: Name, ...fields}`, or the external
    // `"Name"` / `{Name: payload}`.
    readonly property var variants: kind === "enum" ? (field.variants || []) : []
    readonly property string tag: kind === "enum" && field.tag ? field.tag : ""
    function variantName(v) {
        if (tag) return v && typeof v === "object" ? String(v[tag] || "") : "";
        if (typeof v === "string") return v;
        if (v && typeof v === "object") { const keys = Object.keys(v); return keys.length ? keys[0] : ""; }
        return "";
    }
    readonly property var variant: variants.find(x => x.name === variantName(value)) || null
    function variantValue(t, variant, old) {
        const hasFields = variant.fields && variant.fields.length;
        const body = hasFields ? zeroOf({ type: "struct", fields: variant.fields }) : null;
        if (t.tag) {
            const out = Object.assign({}, body || {});
            out[t.tag] = variant.name;
            return out;
        }
        if (!hasFields && !variant.inner) return variant.name;
        const out = {};
        out[variant.name] = variant.inner ? zeroOf(variant.inner) : body;
        return out;
    }
    // The fields of the current variant as a plain record, and back.
    function variantBody() {
        if (!variant) return ({});
        if (tag) return value || ({});
        return value && typeof value === "object" ? value[variant.name] : null;
    }
    function withVariantBody(next) {
        if (tag) { const out = Object.assign({}, next); out[tag] = variant.name; return out; }
        const out = {};
        out[variant.name] = next;
        return out;
    }

    readonly property var items: kind === "list" ? (toArray(value) || []) : []

    RowLayout {
        Layout.fillWidth: true
        spacing: 4
        visible: root.kind !== "list" && root.kind !== "struct"
        Loader {
            id: editor
            Layout.fillWidth: true
            sourceComponent: {
                if (root.hostEditor) return root.hostEditor;
                if (root.widget === "slider" && root.present(root.field.min) && root.present(root.field.max)) return sliderEditor;
                if (root.widget === "multiline") return multilineEditor;
                return ({ bool: boolEditor, int: numberEditor, number: numberEditor, text: textEditor,
                          color: textEditor, asset: textEditor, actor: textEditor, vec3: vec3Editor,
                          choice: choiceEditor, optional: optionalEditor, enum: enumEditor,
                          map: jsonEditor, opaque: jsonEditor })[root.kind] || textEditor;
            }
            onLoaded: {
                if (!root.hostEditor) return;
                item.field = Qt.binding(() => root.field);
                item.value = Qt.binding(() => root.value);
                if (item.hasOwnProperty("host")) item.host = Qt.binding(() => root.host);
            }
            Connections {
                target: root.hostEditor ? editor.item : null
                ignoreUnknownSignals: true
                function onEdited(next) { root.edited(next); }
            }
        }
        Text {
            visible: root.unit !== "" && root.kind !== "optional"
            text: root.unit; color: Theme.textDim; font.pixelSize: 11
        }
    }

    Component { id: boolEditor
        RowLayout {
            StitchSwitch { objectName: "property-switch"; checked: root.value === true; onToggled: on => root.edited(on) }
            Item { Layout.fillWidth: true }
        } }
    Component { id: numberEditor
        StitchTextField {
            objectName: "property-number"
            implicitHeight: 30; font.pixelSize: 12; selectByMouse: true
            text: root.shown(root.value)
            onEditingFinished: {
                const n = Number(text.trim());
                if (text.trim() === "" || !Number.isFinite(n)) { text = root.shown(root.value); return; }
                const next = root.clamp(n);
                if (next !== root.value) root.edited(next);
                text = root.shown(next);
            }
        } }
    Component { id: textEditor
        StitchTextField {
            objectName: "property-text"
            implicitHeight: 30; font.pixelSize: 12; selectByMouse: true
            maximumLength: root.present(root.field.max_len) ? root.field.max_len : 32767
            text: root.present(root.value) ? String(root.value) : ""
            onEditingFinished: if (text !== String(root.value === null ? "" : root.value)) root.edited(text)
        } }
    Component { id: multilineEditor
        Rectangle {
            implicitHeight: 72; radius: 4; color: Theme.field; border.width: 1; border.color: Theme.border
            TextArea {
                objectName: "property-multiline"
                anchors.fill: parent; font.pixelSize: 12; color: Theme.text; wrapMode: TextEdit.Wrap; background: null
                text: root.present(root.value) ? String(root.value) : ""
                onEditingFinished: if (text !== String(root.value === null ? "" : root.value)) root.edited(text)
            }
        } }
    Component { id: sliderEditor
        RowLayout {
            spacing: 8
            StitchSlider {
                objectName: "property-slider"
                Layout.fillWidth: true
                from: root.field.min; to: root.field.max
                stepSize: root.field.ui && root.field.ui.step ? root.field.ui.step : (root.kind === "int" ? 1 : 0)
                value: Number(root.value) || 0
                onMoved: root.edited(root.clamp(value))
            }
            Text { text: root.shown(root.value); color: Theme.textDim; font.pixelSize: 11; Layout.preferredWidth: 36 }
        } }
    Component { id: vec3Editor
        RowLayout {
            spacing: 4
            Repeater {
                model: 3
                delegate: StitchTextField {
                    required property int index
                    readonly property var v: root.toArray(root.value) || [0, 0, 0]
                    Layout.fillWidth: true; Layout.minimumWidth: 40
                    implicitHeight: 30; font.pixelSize: 12; selectByMouse: true
                    text: root.shown(v[index])
                    onEditingFinished: {
                        const n = Number(text.trim());
                        if (!Number.isFinite(n) || text.trim() === "") { text = root.shown(v[index]); return; }
                        const next = v.slice(); next[index] = n;
                        root.edited(next);
                    }
                }
            }
        } }
    Component { id: choiceEditor
        StitchComboBox {
            objectName: "property-choice"
            implicitHeight: 30; font.pixelSize: 12
            model: root.field.options || []
            currentIndex: (root.field.options || []).indexOf(root.value)
            onActivated: i => { const v = root.field.options[i]; if (v !== root.value) root.edited(v); }
        } }
    Component { id: jsonEditor
        StitchTextField {
            objectName: "property-json"
            implicitHeight: 30; font.pixelSize: 12; selectByMouse: true
            text: root.present(root.value) ? JSON.stringify(root.value) : ""
            onEditingFinished: {
                if (text.trim() === "") { if (root.value !== null) root.edited(null); return; }
                try { root.edited(JSON.parse(text)); } catch (e) { text = JSON.stringify(root.value); }
            }
        } }
    // An optional is a switch, then its value while it has one.
    Component { id: optionalEditor
        RowLayout {
            spacing: 6
            StitchSwitch {
                objectName: "property-optional"
                checked: root.present(root.value)
                onToggled: on => root.edited(on ? (root.present(root.field.default) ? root.field.default : root.zeroOf(root.field.inner)) : null)
            }
            Loader {
                id: optional
                Layout.fillWidth: true
                active: root.present(root.value)
                source: Qt.resolvedUrl("PropertyEditor.qml")
                onLoaded: {
                    item.field = Qt.binding(() => Object.assign({ ui: root.field.ui }, root.field.inner || { type: "opaque" }));
                    item.value = Qt.binding(() => root.value);
                    item.record = Qt.binding(() => root.record);
                    item.editors = Qt.binding(() => root.editors);
                    item.host = Qt.binding(() => root.host);
                }
                Connections { target: optional.item; function onEdited(next) { root.edited(next); } }
            }
            Item { visible: !optional.active; Layout.fillWidth: true }
        } }
    // An enum is its variant's name, then that variant's own fields.
    Component { id: enumEditor
        StitchComboBox {
            objectName: "property-variant"
            implicitHeight: 30; font.pixelSize: 12
            model: root.variants.map(v => v.name)
            currentIndex: root.variants.findIndex(v => root.variant && v.name === root.variant.name)
            onActivated: i => {
                const picked = root.variants[i];
                if (root.variant && picked.name === root.variant.name) return;
                root.edited(root.variantValue(root.field, picked, root.value));
            }
        } }
    Loader {
        id: variantBody
        Layout.fillWidth: true
        Layout.leftMargin: 10
        active: root.kind === "enum" && !!root.variant && ((root.variant.fields || []).length > 0 || !!root.variant.inner)
        visible: active
        source: !active ? "" : root.variant.inner ? Qt.resolvedUrl("PropertyEditor.qml") : Qt.resolvedUrl("PropertyForm.qml")
        onLoaded: {
            item.record = Qt.binding(() => root.record);
            item.editors = Qt.binding(() => root.editors);
            item.host = Qt.binding(() => root.host);
            item.width = Qt.binding(() => variantBody.width);
            if (root.variant.inner) {
                item.field = Qt.binding(() => root.variant ? root.variant.inner : ({ type: "opaque" }));
                item.value = Qt.binding(() => root.variantBody());
            } else {
                item.labelWidth = Qt.binding(() => root.labelWidth - 10);
                item.fields = Qt.binding(() => root.variant ? root.variant.fields : []);
                item.value = Qt.binding(() => root.variantBody() || ({}));
            }
        }
        Connections {
            target: variantBody.item
            ignoreUnknownSignals: true
            function onChanged(next) { root.edited(root.withVariantBody(next)); }
            function onEdited(next) { root.edited(root.withVariantBody(next)); }
        }
    }

    // A struct as a value (a list item, say) is its own form.
    Loader {
        id: structForm
        Layout.fillWidth: true
        active: root.kind === "struct"
        visible: active
        source: active ? Qt.resolvedUrl("PropertyForm.qml") : ""
        onLoaded: {
            item.fields = Qt.binding(() => root.field.fields || []);
            item.value = Qt.binding(() => root.value || ({}));
            item.record = Qt.binding(() => root.record);
            item.editors = Qt.binding(() => root.editors);
            item.host = Qt.binding(() => root.host);
            item.labelWidth = Qt.binding(() => root.labelWidth);
            item.width = Qt.binding(() => structForm.width);
        }
        Connections { target: structForm.item; function onChanged(next) { root.edited(next); } }
    }

    // A list is its items, each edited as its own value, and a way to add one.
    Repeater {
        model: root.kind === "list" ? root.items.length : 0
        delegate: RowLayout {
            id: entry
            required property int index
            Layout.fillWidth: true
            spacing: 4
            Loader {
                id: itemLoader
                Layout.fillWidth: true
                source: Qt.resolvedUrl("PropertyEditor.qml")
                onLoaded: {
                    item.field = Qt.binding(() => root.field.item || ({ type: "text" }));
                    item.value = Qt.binding(() => root.items[entry.index]);
                    item.record = Qt.binding(() => root.record);
                    item.editors = Qt.binding(() => root.editors);
                    item.host = Qt.binding(() => root.host);
                    item.labelWidth = Qt.binding(() => root.labelWidth);
                    item.width = Qt.binding(() => itemLoader.width);
                }
                Connections {
                    target: itemLoader.item
                    function onEdited(next) {
                        const list = root.items.slice();
                        list[entry.index] = next;
                        root.edited(list);
                    }
                }
            }
            StitchButton {
                objectName: "property-remove"
                iconName: "x"; implicitWidth: 26; implicitHeight: 26
                Layout.alignment: Qt.AlignTop
                ToolTip.visible: hovered; ToolTip.text: qsTr("Remove this item"); ToolTip.delay: 600
                onClicked: { const list = root.items.slice(); list.splice(entry.index, 1); root.edited(list); }
            }
        }
    }
    StitchButton {
        objectName: "property-add"
        visible: root.kind === "list" && (!root.present(root.field.max_len) || root.items.length < root.field.max_len)
        iconName: "plus"; text: qsTr("Add item"); implicitHeight: 28; font.pixelSize: 12
        onClicked: root.edited(root.items.concat([root.zeroOf(root.field.item || ({ type: "text" }))]))
    }
}
