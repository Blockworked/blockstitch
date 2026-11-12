pragma Singleton
import QtQuick
import QtQuick.Controls

// Shared entry points for block choices, declarative forms and native pickers.
QtObject {
    id: ui
    function choices(options, instruction) {
        if (typeof options === "function") return options(instruction) || [];
        return Array.isArray(options) ? options : [];
    }
    // Native screens stay in the host; all row buttons use the same router.
    function open(action, request, screens) {
        const screen = screens && screens[action];
        if (!screen) return false;
        screen(request);
        return true;
    }
    property Component form: Component { BlockSettingsDialog {} }
    function openForm(owner, title, fields, values, commit) {
        const dialog = form.createObject(owner, {title: title, fields: fields, values: values});
        if (!dialog) return null;
        dialog.applyRequested.connect(changes => {
            const error = commit(changes);
            if (error) dialog.errorText = error;
            else dialog.accept();
        });
        dialog.closed.connect(() => Qt.callLater(() => dialog.destroy()));
        dialog.open();
        return dialog;
    }
    function customFields(definition, button) {
        const inputs = (definition.pieces || []).filter(p => p.kind === "Input");
        return (button.inputs || []).map(id => {
            const index = inputs.findIndex(p => p.id === id), input = inputs[index];
            return input ? {id: id, index: index, label: input.name,
                bool: input.value_type === "Bool", multiline: !!input.multiline,
                choices: input.ui ? input.ui.choices || [] : []} : null;
        }).filter(f => f !== null);
    }
    // Only touched arguments are replaced, and a changed target is refused.
    function applyCustom(definition, button, before, current, changes) {
        const fields = customFields(definition, button), result = JSON.parse(JSON.stringify(current));
        result.args = result.args || [];
        for (const id of Object.keys(changes)) {
            const field = fields.find(f => f.id === id);
            if (!field) return {error: qsTr("The block's inputs changed. Reopen its settings.")};
            if (JSON.stringify((before.args || [])[field.index]) !== JSON.stringify(result.args[field.index]))
                return {error: qsTr("An input changed while this screen was open. Reopen its settings.")};
            result.args[field.index] = changes[id];
        }
        return {value: result};
    }
    function openCustom(owner, definition, buttonId, before, current, commit) {
        const button = (definition.pieces || []).find(p => p.kind === "Button" && p.id === buttonId);
        if (!button) return null;
        const schema = JSON.stringify(definition.pieces), fields = customFields(definition, button);
        const values = fields.reduce((out, f) => { out[f.id] = (before.args || [])[f.index]; return out; }, {});
        const dialog = openForm(owner, button.title, fields, values, changes => {
            if (!Object.keys(changes).length) return "";
            const target = current();
            if (!target || !target.definition || JSON.stringify(target.definition.pieces) !== schema)
                return qsTr("The block changed. Reopen its settings.");
            const result = applyCustom(definition, button, before, target.value, changes);
            if (result.error) return result.error;
            return commit(result.value) || "";
        });
        if (dialog) dialog.blockDefinitions = owner.blockDefinitions || [];
        return dialog;
    }
}
