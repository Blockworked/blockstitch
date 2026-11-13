// Rows the tests' sample blocks use. Blockstitch has no built-in rows for
// host blocks such as Wait, so a test registers the ones it draws.
function register(registry) {
    registry.registerRows({
        Wait: { icon: "clock", head: [{ kind: "label", text: "Wait" },
            { kind: "value", field: "WaitDuration", key: "duration", unit: "ms" }] }
    });
}
