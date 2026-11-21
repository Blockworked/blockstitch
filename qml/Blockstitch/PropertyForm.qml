import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// A form over one record, built from its field schemas (the shape a host's
// type registry lists: name, type, default, ui hints). It only asks: it shows
// `value` and reports `changed(next)` with the whole next record, keeping any
// key the schema doesn't name, so an older schema never trims a newer record.
ColumnLayout {
    id: root
    property var fields: []
    property var value: ({})
    // The top of what is being edited, for conditions starting with `/`.
    property var record: value
    // Headings over named fields ([{label, fields, collapsed}]), drawn after
    // the fields no group names. Fields with `ui.group` join a group too.
    property var groups: []
    // Editors the host supplies by field type (`color`, `asset`, ...). Each
    // has `field`, `value`, optional `host`, and a `edited(next)` signal.
    property var editors: ({})
    // Handed to host editors as `host`.
    property var host: null
    property real labelWidth: 78
    signal changed(var next)
    spacing: 6

    // "bar_color" reads as "Bar color".
    function labelOf(field) {
        if (field.ui && field.ui.label) return field.ui.label;
        const spaced = String(field.name).replace(/_/g, " ");
        return spaced.charAt(0).toUpperCase() + spaced.slice(1);
    }
    function defaultOf(field) { return field.default === undefined ? null : field.default; }
    function valueOf(field) {
        const held = root.value ? root.value[field.name] : undefined;
        return held === undefined ? root.defaultOf(field) : held;
    }
    function withField(field, next) {
        const out = Object.assign({}, root.value || {});
        out[field.name] = next;
        return out;
    }

    // A condition's field: a sibling, a dotted path below one, or `/path`
    // from the top. A missing sibling reads as its schema default.
    function read(path) {
        const fromTop = path.charAt(0) === "/";
        const steps = (fromTop ? path.slice(1) : path).split(".");
        let at;
        if (fromTop) at = root.record;
        else {
            const first = root.fields.find(f => f.name === steps[0]);
            at = first ? root.valueOf(first) : (root.value ? root.value[steps[0]] : undefined);
            steps.shift();
        }
        for (const s of steps) at = at === null || at === undefined ? undefined : at[s];
        return at === undefined ? null : at;
    }
    function same(a, b) { return JSON.stringify(a) === JSON.stringify(b); }
    function truthy(v) { return Array.isArray(v) ? v.length > 0 : !!v; }
    function holds(when) {
        if (!when) return true;
        for (const part of when.all || []) if (!root.holds(part)) return false;
        if (!when.field) return true;
        const now = root.read(when.field);
        if (when.equals !== undefined && when.equals !== null) return root.same(now, when.equals);
        if (when.not_equals !== undefined && when.not_equals !== null) return !root.same(now, when.not_equals);
        if (when.one_of && when.one_of.length) return when.one_of.some(v => root.same(now, v));
        if (when.not_one_of && when.not_one_of.length) return !when.not_one_of.some(v => root.same(now, v));
        return root.truthy(now);
    }
    function shown(field) { return root.holds(field.ui ? field.ui.visible_when : null); }

    // Sections in drawing order: ungrouped fields, then each group.
    readonly property var sections: {
        const fields = root.fields || [];
        const named = [];
        const byLabel = {};
        const placed = {};
        const group = (label, collapsed) => {
            if (!byLabel[label]) { byLabel[label] = { label: label, collapsed: collapsed, members: [] }; named.push(byLabel[label]); }
            return byLabel[label];
        };
        for (const g of root.groups || []) {
            const into = group(g.label || "", !!g.collapsed);
            for (const name of g.fields || []) {
                const i = fields.findIndex(f => f.name === name);
                if (i >= 0 && !placed[name]) { into.members.push(i); placed[name] = true; }
            }
        }
        fields.forEach((f, i) => {
            if (placed[f.name] || !f.ui) return;
            if (f.ui.group) { group(f.ui.group, false).members.push(i); placed[f.name] = true; }
            else if (f.ui.advanced) { group("Advanced", true).members.push(i); placed[f.name] = true; }
        });
        const loose = [];
        fields.forEach((f, i) => { if (!placed[f.name]) loose.push(i); });
        return (loose.length ? [{ label: "", collapsed: false, members: loose }] : []).concat(named);
    }
    // Headings the user has flipped from how the schema starts them.
    property var flipped: ({})
    function isOpen(section) { return root.flipped[section.label] ? section.collapsed : !section.collapsed; }
    function flip(label) { const next = Object.assign({}, root.flipped); next[label] = !next[label]; root.flipped = next; }

    Repeater {
        model: root.sections
        delegate: ColumnLayout {
            id: section
            required property var modelData
            readonly property bool open: root.isOpen(section.modelData)
            objectName: "property-section-" + section.modelData.label
            Layout.fillWidth: true
            spacing: 6
            Heading {
                visible: section.modelData.label !== ""
                text: section.modelData.label
                open: section.open
                onClicked: root.flip(section.modelData.label)
            }
            Repeater {
                model: section.open ? section.modelData.members : []
                delegate: Loader {
                    id: row
                    required property int modelData
                    readonly property var field: root.fields[row.modelData]
                    readonly property bool nested: row.field.type === "struct"
                    objectName: "property-row-" + row.field.name
                    visible: root.shown(row.field)
                    active: visible
                    Layout.fillWidth: true
                    sourceComponent: row.nested ? nestedRow : plainRow

                    Component {
                        id: plainRow
                        RowLayout {
                            spacing: 6
                            Text {
                                Layout.preferredWidth: root.labelWidth
                                Layout.alignment: Qt.AlignTop
                                topPadding: 7
                                text: root.labelOf(row.field)
                                color: Theme.textDim; font.pixelSize: 12; elide: Text.ElideRight
                                HoverHandler { id: labelHover }
                                ToolTip.visible: labelHover.hovered && !!row.field.description
                                ToolTip.text: row.field.description || ""
                                ToolTip.delay: 600
                            }
                            PropertyEditor {
                                Layout.fillWidth: true
                                field: row.field
                                value: root.valueOf(row.field)
                                record: root.record
                                editors: root.editors
                                host: root.host
                                labelWidth: root.labelWidth
                                onEdited: next => root.changed(root.withField(row.field, next))
                            }
                        }
                    }
                    Component {
                        id: nestedRow
                        ColumnLayout {
                            id: nest
                            property bool open: !(row.field.ui && row.field.ui.advanced)
                            spacing: 6
                            Heading { text: root.labelOf(row.field); open: nest.open; onClicked: nest.open = !nest.open }
                            Loader {
                                id: inner
                                visible: nest.open
                                active: nest.open
                                Layout.fillWidth: true
                                Layout.leftMargin: 10
                                // Through a Loader: a file can't name its own type.
                                source: Qt.resolvedUrl("PropertyForm.qml")
                                onLoaded: {
                                    item.fields = Qt.binding(() => row.field.fields || []);
                                    item.value = Qt.binding(() => root.valueOf(row.field) || ({}));
                                    item.record = Qt.binding(() => root.record);
                                    item.editors = Qt.binding(() => root.editors);
                                    item.host = Qt.binding(() => root.host);
                                    item.labelWidth = Qt.binding(() => root.labelWidth - 10);
                                    item.width = Qt.binding(() => inner.width);
                                }
                                Connections {
                                    target: inner.item
                                    function onChanged(next) { root.changed(root.withField(row.field, next)); }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    component Heading: MouseArea {
        id: heading
        property string text
        property bool open: true
        Layout.fillWidth: true
        implicitHeight: visible ? 22 : 0
        cursorShape: Qt.PointingHandCursor
        Row {
            anchors.verticalCenter: parent.verticalCenter
            spacing: 4
            LucideIcon {
                anchors.verticalCenter: parent.verticalCenter
                name: heading.open ? "chevron-down" : "chevron-right"
                width: 13; height: 13; color: Theme.textDim
            }
            Text { text: heading.text; color: Theme.text; font.pixelSize: 12; font.weight: Font.DemiBold }
        }
    }
}
