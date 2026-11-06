import QtQuick

// The canvas's strands as a ListModel keyed by strand id. A Repeater over a
// plain array recreates every delegate when the host pushes new state; this
// keeps untouched strands alive, so moves only touch x/y and edits only
// touch that strand. Instructions are a JSON string role: a JS array role
// doesn't round-trip through ListModel.
ListModel {
    id: model
    // Makes the model match `list`, calling changing() before each change.
    function sync(list, changing) {
        for (let i = model.count - 1; i >= 0; --i) {
            const sid = model.get(i).sid;
            let alive = false;
            for (let j = 0; j < list.length; ++j)
                if (list[j].id === sid) {
                    alive = true;
                    break;
                }
            if (!alive) {
                changing();
                model.remove(i);
            }
        }
        for (let j = 0; j < list.length; ++j) {
            const s = list[j];
            const payload = JSON.stringify(s.instructions || []);
            let at = -1;
            for (let i = 0; i < model.count; ++i)
                if (model.get(i).sid === s.id) {
                    at = i;
                    break;
                }
            if (at === -1) {
                changing();
                model.insert(j, {
                    sid: s.id,
                    sx: s.x,
                    sy: s.y,
                    payload: payload
                });
            } else {
                if (at !== j) {
                    changing();
                    model.move(at, j, 1);
                    at = j;
                }
                const row = model.get(at);
                if (row.sx !== s.x) {
                    changing();
                    model.setProperty(at, "sx", s.x);
                }
                if (row.sy !== s.y) {
                    changing();
                    model.setProperty(at, "sy", s.y);
                }
                if (row.payload !== payload) {
                    changing();
                    model.setProperty(at, "payload", payload);
                }
            }
        }
        while (model.count > list.length) {
            changing();
            model.remove(model.count - 1);
        }
    }
}
