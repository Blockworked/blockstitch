pragma Singleton
import QtQuick

// What a host's blocks look like, as data - the QML side of the Vue
// frontend's register* calls. Built-in tables cover blockstitch's own
// operators and the classic Blockwork block set, so a host that registers
// nothing gets the old behaviour; `registerRows`/`registerOperators` add to
// or override them.
QtObject {
    id: registry

    // Names the list/dict reporters and name dropdowns offer. BlockCanvas
    // keeps these in step with the document it shows.
    property var listNames: []
    property var dictNames: []
    // Bump to re-evaluate option lists that read host state through a function.
    property int revision: 0
    // Whether block menus offer "Set Recording Target" (a Blockwork feature).
    property bool recordingTargets: true
    // Kept in step with the canvas so block menus can label themselves.
    property string recordingTargetId: ""
    property var commentedIds: []
    // Host markers on canvas blocks, instruction id -> message (an error
    // from the last run, say). Clicking one emits markClicked.
    property var blockMarks: ({})
    signal markClicked(string instructionId)
    // Instruction ids the host's running strands are on, outlined live.
    property var runningIds: []
    // Debugger: blocks with a breakpoint get a dot (clicking it emits
    // breakpointClicked), and blocks a strand is paused at get an outline.
    property var breakpointIds: []
    property var pausedIds: []
    signal breakpointClicked(string instructionId)
    // Outlined for a moment after BlockCanvas.revealInstruction.
    property string flashId: ""
    function flash(id) { flashId = id; flashTimer.restart(); }
    property var flashTimer: Timer { interval: 1600; onTriggered: registry.flashId = "" }
    // Extra right-click entries a host adds: [{id, text, icon, danger}]. A
    // choice comes back as BlockCanvas.blockMenuAction / canvasMenuAction.
    property var blockMenu: []
    property var canvasMenu: []

    // Click-to-preview: a click on a reporter calls `previewHandler(key, value)`
    // and the host answers with `deliverPreview(key, text, isError)`. The
    // result shows beside the chip that asked, then clears itself.
    property var previewHandler: null
    property var preview: null   // {key, text, error}
    property int previewSerial: 0
    function requestPreview(key, value) { if (previewHandler) previewHandler(key, value); }
    function deliverPreview(key, text, isError) {
        preview = { key: key, text: text, error: !!isError };
        previewTimer.restart();
    }
    function nextPreviewKey() { return "preview-" + (++previewSerial); }
    property var previewTimer: Timer { interval: 2500; onTriggered: registry.preview = null }

    // type -> { shape, icon, head: [piece], mouths: [key], separators: [text] }
    // `head` may be a function(instruction) -> [piece] for a type whose row
    // depends on the instruction. Return the same piece objects each time:
    // a changed array rebuilds the row's controls.
    // piece: {kind:"label",text} | {kind:"value",field,key,index,bool}
    //      | {kind:"dropdown",key,index,options,placeholder,encode,decode}
    //      | {kind:"text",key,index,placeholder}
    // A piece's `index`, when set, picks one entry of the array held under
    // `key`; without it `key` holds the value itself.
    // Any piece may carry `when: function(instruction) -> bool`.
    // `options` is an array of {value,label}, a function(instruction), or
    // "lists"/"dicts" for the document's names.
    property var rows: ({})
    // op -> { prefix, infix (one label, or a list: one per gap), suffix, result, enumArg: {index, options|source}, oneBased: [index] }
    // An operator may instead give `layout`: [piece] or function(value) -> [piece],
    // piece {label, arg: -1} | {arg, bool}, `arg` indexing the value's args. Args no
    // piece names are not drawn (a host's generic operator keeps its
    // identity there). Return the same objects each time.
    property var operators: defaultOperators()
    // type -> instruction fields a fresh palette block starts with
    property var prefabs: ({})

    function registerRows(map) { rows = Object.assign({}, rows, map); }
    function registerOperators(map) { operators = Object.assign({}, operators, map); }
    // Back to the built-in operators, labelled in the current language; a
    // host re-registers its own after this.
    function resetOperators() { operators = defaultOperators(); }
    function registerPrefabs(map) { prefabs = Object.assign({}, prefabs, map); }

    function defaultOperators() {
        const mathOptions = [
            {value:"Abs",label:qsTr("abs")},{value:"Floor",label:qsTr("floor")},{value:"Ceiling",label:qsTr("ceiling")},{value:"Sign",label:qsTr("sign")},
            {value:"Sqrt",label:qsTr("sqrt")},{value:"Sin",label:qsTr("sin")},{value:"Cos",label:qsTr("cos")},{value:"Tan",label:qsTr("tan")},
            {value:"Asin",label:qsTr("asin")},{value:"Acos",label:qsTr("acos")},{value:"Atan",label:qsTr("atan")},{value:"Ln",label:qsTr("ln")},
            {value:"Log",label:qsTr("log")},{value:"Log2",label:qsTr("log2")},{value:"EPower",label:qsTr("e ^")},{value:"TenPower",label:"10 ^"}
        ];
        const caseOptions = [{value:"Upper",label:qsTr("uppercase")},{value:"Lower",label:qsTr("lowercase")}];
        const timeOptions = [
            {value:"Year",label:qsTr("year")},{value:"Month",label:qsTr("month")},{value:"Date",label:qsTr("date")},{value:"DayOfWeek",label:qsTr("day of week")},
            {value:"Hour",label:qsTr("hour")},{value:"Minute",label:qsTr("minute")},{value:"Second",label:qsTr("second")}
        ];
        const n = "number", t = "text", b = "bool";
        return {
            Add:{infix:"+",result:n}, Sub:{infix:"−",result:n}, Mul:{infix:"×",result:n}, Div:{infix:"/",result:n}, Mod:{infix:qsTr("mod"),result:n},
            Round:{prefix:qsTr("round"),result:n}, Math:{infix:qsTr("of"),result:n,enumArg:{index:0,options:mathOptions}},
            Random:{prefix:qsTr("pick random"),infix:qsTr("to"),result:n},
            Join:{prefix:qsTr("join"),result:t}, NewLine:{prefix:qsTr("new line"),result:t}, Tab:{prefix:qsTr("tab character"),result:t},
            IndexOf:{prefix:qsTr("index of"),infix:qsTr("in"),result:n}, LastIndexOf:{prefix:qsTr("last index of"),infix:qsTr("in"),result:n},
            LetterOf:{prefix:qsTr("letter"),infix:qsTr("of"),result:t}, Length:{prefix:qsTr("length of"),result:n},
            Case:{infix:qsTr("to"),result:t,enumArg:{index:1,options:caseOptions}},
            Eq:{infix:"=",result:b}, Neq:{infix:"≠",result:b}, Gt:{infix:">",result:b}, Lt:{infix:"<",result:b},
            Gte:{infix:"≥",result:b}, Lte:{infix:"≤",result:b}, And:{infix:qsTr("and"),result:b}, Or:{infix:qsTr("or"),result:b},
            Not:{prefix:qsTr("not"),result:b}, True:{prefix:qsTr("true"),result:b}, False:{prefix:qsTr("false"),result:b},
            CurrentTime:{prefix:qsTr("current"),result:n,enumArg:{index:0,options:timeOptions}},
            BatteryPercentage:{prefix:qsTr("battery percentage"),result:n}, PluggedIn:{prefix:qsTr("plugged in?"),result:b},
            ClipboardText:{prefix:qsTr("clipboard text"),result:t}, ClipboardHasImage:{prefix:qsTr("clipboard has image"),result:b},
            ClipboardHasFiles:{prefix:qsTr("clipboard has files"),result:b},
            ListItem:{prefix:qsTr("item"),infix:qsTr("of"),result:t,enumArg:{index:1,source:"lists"},oneBased:[0]},
            ListItemNumber:{prefix:qsTr("item # of"),infix:qsTr("in"),result:n,enumArg:{index:1,source:"lists"}},
            ListAmount:{prefix:qsTr("amount of"),infix:qsTr("in"),result:n,enumArg:{index:1,source:"lists"}},
            ListLength:{prefix:qsTr("length of"),result:n,enumArg:{index:0,source:"lists"}},
            ListContains:{infix:qsTr("contains"),result:b,enumArg:{index:0,source:"lists"}},
            ListItemExists:{prefix:qsTr("item"),infix:qsTr("exists in"),result:b,enumArg:{index:1,source:"lists"},oneBased:[0]},
            ListIsEmpty:{prefix:qsTr("is"),suffix:qsTr("empty?"),result:b,enumArg:{index:0,source:"lists"}},
            ListAsJson:{suffix:qsTr("as JSON"),result:t,enumArg:{index:0,source:"lists"}},
            DictValue:{prefix:qsTr("value"),infix:qsTr("in"),result:t,enumArg:{index:1,source:"dicts"}},
            DictHasKey:{infix:qsTr("has key"),result:b,enumArg:{index:0,source:"dicts"}},
            DictSize:{prefix:qsTr("size of"),result:n,enumArg:{index:0,source:"dicts"}},
            DictKeys:{prefix:qsTr("keys of"),result:t,enumArg:{index:0,source:"dicts"}},
            DictAsJson:{suffix:qsTr("as JSON"),result:t,enumArg:{index:0,source:"dicts"}},
            DictIsEmpty:{prefix:qsTr("is"),suffix:qsTr("empty?"),result:b,enumArg:{index:0,source:"dicts"}}
        };
    }

    function operator(op) { return (op && operators[op]) || null; }
    // `result` may be a function(value) for an operator whose type depends on
    // the value (a host's generic operator).
    function isBoolOp(op, value) {
        const s = operator(op);
        if (!s) return false;
        return (typeof s.result === "function" ? s.result(value) : s.result) === "bool";
    }

    // The {value,label} choices an enum slot offers right now.
    function choices(options, instruction) {
        revision;
        if (options === "lists") return nameChoices(listNames, "list");
        if (options === "dicts") return nameChoices(dictNames, "dict");
        if (typeof options === "function") return options(instruction) || [];
        return options || [];
    }
    function nameChoices(names, fallback) {
        const list = (names || []).map(n => ({ value: n, label: n }));
        return list.length ? list : [{ value: "", label: fallback }];
    }
    function enumChoices(enumArg) {
        if (!enumArg) return [];
        return choices(enumArg.source || enumArg.options, null);
    }

    function row(type) { return rows[type] || null; }
    function iconFor(type) {
        const r = row(type);
        if (r && r.icon) return r.icon;
        const p={WhenRan:"play",WhenBatteryDischargedTo:"battery-warning",WhenBatteryChargedTo:"battery-charging",WhenTime:"clock",WhenPowerPluggedIn:"plug-zap",WhenPowerUnplugged:"unplug",WhenClipboardChanged:"clipboard-check",WhenKey:"keyboard",Wait:"clock",Text:"text-cursor",Key:"keyboard",Button:"mouse-pointer-click",MoveMouse:"move",Scroll:"mouse",Command:"terminal",OpenApp:"app-window",CloseApp:"square-x",SetVariable:"equal",ChangeVariable:"trending-up",SetClipboard:"clipboard",AddToList:"plus",DeleteOfList:"trash",DeleteAllOfList:"trash",ShiftList:"arrow-left",InsertIntoList:"plus",ReplaceItemOfList:"repeat",ReverseList:"rotate",Return:"undo",If:"git-branch",IfElse:"git-fork",Repeat:"repeat",Forever:"infinity",While:"rotate",EscapeLoop:"log-out",ContinueLoop:"skip-forward",BlockHeader:"blocks",CallBlock:"blocks",BranchCallBlock:"blocks",RunBranch:"git-branch"};
        return p[type] || "blocks";
    }

    // ---- shapes ----
    function mouthKeys(type) {
        const r = row(type);
        if (r && r.mouths) return r.mouths;
        if (type === "IfElse") return ["then_body", "else_body"];
        if (["If", "Repeat", "Forever", "While"].indexOf(type) >= 0) return ["body"];
        return [];
    }
    function isWrap(type) { return type === "BranchCallBlock" || mouthKeys(type).length > 0; }
    function isHeader(type) {
        const r = row(type);
        if (r && r.shape) return r.shape === "header";
        return type === "BlockHeader" || (!!type && type.indexOf("When") === 0);
    }
    function isCapType(type) {
        const r = row(type);
        if (r && r.shape) return r.shape === "cap";
        return ["Return", "EscapeLoop", "ContinueLoop"].indexOf(type) >= 0;
    }
    // A call to a custom block shaped "Ending" also ends its stack.
    function isCap(ins, defs) {
        if (!ins) return false;
        if (isCapType(ins.type)) return true;
        if ((ins.type === "CallBlock" || ins.type === "BranchCallBlock") && defs) {
            for (let i = 0; i < defs.length; ++i)
                if (defs[i].id === ins.block_id) return defs[i].shape === "Ending";
        }
        return false;
    }
    function slotCount(ins) {
        if (!ins) return 0;
        if (ins.type === "BranchCallBlock") return (ins.branches || []).length;
        return mouthKeys(ins.type).length;
    }
    function body(ins, slot) {
        if (!ins) return [];
        if (ins.type === "BranchCallBlock") return (ins.branches || [])[slot] || [];
        const key = mouthKeys(ins.type)[slot || 0];
        return (key && ins[key]) || [];
    }
    function separator(type, slot) {
        const r = row(type);
        if (r && r.separators) return r.separators[slot] || "";
        return type === "IfElse" ? "else" : "";
    }

    // A fresh instruction of `type` for the palette, or null when the host
    // registered none.
    function prefab(type) {
        const p = prefabs[type];
        if (!p) return null;
        const i = JSON.parse(JSON.stringify(typeof p === "function" ? p() : p));
        i.type = type;
        if (!i.id) i.id = "palette-" + type;
        return i;
    }
}
