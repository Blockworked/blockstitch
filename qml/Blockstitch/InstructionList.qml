import QtQuick

// A list of instructions as a model keyed by id. Syncing a new list keeps
// the delegate of every block whose own JSON didn't change, so an edit only
// rebuilds the blocks it touched instead of the whole stack. Delegates read
// `payload`, the instruction as JSON (a ListModel role can't hold an array).
ListModel {
    id: model
    property var instructions: []
    // Before a run of new rows goes in, so a view can choose how to build them.
    signal aboutToInsert(int at, int n)
    onInstructionsChanged: sync()
    Component.onCompleted: sync()

    function keyOf(ins, j) { return ins && ins.id ? String(ins.id) : "#" + j; }
    function indexOf(key, from) {
        for (let i = from; i < count; ++i) if (get(i).key === key) return i;
        return -1;
    }
    function sync() {
        const list = instructions || [];
        let j = 0;
        while (j < list.length) {
            const key = keyOf(list[j], j);
            const payload = JSON.stringify(list[j]);
            const at = indexOf(key, j);
            if (at < 0) {
                // A run of new blocks (an attach, say) goes in as one insert:
                // one at a time, every later block re-laid out per row.
                const rows = [{ key: key, payload: payload }];
                for (let k = j + 1; k < list.length; ++k) {
                    const next = keyOf(list[k], k);
                    if (indexOf(next, j) >= 0) break;
                    rows.push({ key: next, payload: JSON.stringify(list[k]) });
                }
                aboutToInsert(j, rows.length);
                insert(j, rows);
                j += rows.length;
                continue;
            }
            if (at !== j) move(at, j, 1);
            if (get(j).payload !== payload) setProperty(j, "payload", payload);
            ++j;
        }
        if (count > list.length) remove(list.length, count - list.length);
    }
}
