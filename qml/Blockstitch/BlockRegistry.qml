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
    // Extra right-click entries a host adds: [{id, text, icon, danger}]. A
    // choice comes back as BlockCanvas.blockMenuAction / canvasMenuAction.
    property var blockMenu: []
    property var canvasMenu: []

    // type -> { shape, icon, head: [piece], mouths: [key], separators: [text] }
    // piece: {kind:"label",text} | {kind:"value",field,key,bool}
    //      | {kind:"dropdown",key,options,placeholder,encode,decode}
    //      | {kind:"text",key,placeholder}
    // Any piece may carry `when: function(instruction) -> bool`.
    // `options` is an array of {value,label}, a function(instruction), or
    // "lists"/"dicts" for the document's names.
    property var rows: ({})
    // op -> { prefix, infix, suffix, result, enumArg: {index, options|source}, oneBased: [index] }
    property var operators: defaultOperators()
    // type -> instruction fields a fresh palette block starts with
    property var prefabs: ({})

    function registerRows(map) { rows = Object.assign({}, rows, map); }
    function registerOperators(map) { operators = Object.assign({}, operators, map); }
    function registerPrefabs(map) { prefabs = Object.assign({}, prefabs, map); }

    function defaultOperators() {
        const mathOptions = [
            {value:"Abs",label:"abs"},{value:"Floor",label:"floor"},{value:"Ceiling",label:"ceiling"},{value:"Sign",label:"sign"},
            {value:"Sqrt",label:"sqrt"},{value:"Sin",label:"sin"},{value:"Cos",label:"cos"},{value:"Tan",label:"tan"},
            {value:"Asin",label:"asin"},{value:"Acos",label:"acos"},{value:"Atan",label:"atan"},{value:"Ln",label:"ln"},
            {value:"Log",label:"log"},{value:"Log2",label:"log2"},{value:"EPower",label:"e ^"},{value:"TenPower",label:"10 ^"}
        ];
        const caseOptions = [{value:"Upper",label:"uppercase"},{value:"Lower",label:"lowercase"}];
        const timeOptions = [
            {value:"Year",label:"year"},{value:"Month",label:"month"},{value:"Date",label:"date"},{value:"DayOfWeek",label:"day of week"},
            {value:"Hour",label:"hour"},{value:"Minute",label:"minute"},{value:"Second",label:"second"}
        ];
        const n = "number", t = "text", b = "bool";
        return {
            Add:{infix:"+",result:n}, Sub:{infix:"−",result:n}, Mul:{infix:"×",result:n}, Div:{infix:"/",result:n}, Mod:{infix:"mod",result:n},
            Round:{prefix:"round",result:n}, Math:{infix:"of",result:n,enumArg:{index:0,options:mathOptions}},
            Random:{prefix:"pick random",infix:"to",result:n},
            Join:{prefix:"join",result:t}, NewLine:{prefix:"new line",result:t}, Tab:{prefix:"tab character",result:t},
            IndexOf:{prefix:"index of",infix:"in",result:n}, LastIndexOf:{prefix:"last index of",infix:"in",result:n},
            LetterOf:{prefix:"letter",infix:"of",result:t}, Length:{prefix:"length of",result:n},
            Case:{infix:"to",result:t,enumArg:{index:1,options:caseOptions}},
            Eq:{infix:"=",result:b}, Neq:{infix:"≠",result:b}, Gt:{infix:">",result:b}, Lt:{infix:"<",result:b},
            Gte:{infix:"≥",result:b}, Lte:{infix:"≤",result:b}, And:{infix:"and",result:b}, Or:{infix:"or",result:b},
            Not:{prefix:"not",result:b}, True:{prefix:"true",result:b}, False:{prefix:"false",result:b},
            CurrentTime:{prefix:"current",result:n,enumArg:{index:0,options:timeOptions}},
            BatteryPercentage:{prefix:"battery percentage",result:n}, PluggedIn:{prefix:"plugged in?",result:b},
            ClipboardText:{prefix:"clipboard text",result:t}, ClipboardHasImage:{prefix:"clipboard has image",result:b},
            ClipboardHasFiles:{prefix:"clipboard has files",result:b},
            ListItem:{prefix:"item",infix:"of",result:t,enumArg:{index:1,source:"lists"},oneBased:[0]},
            ListItemNumber:{prefix:"item # of",infix:"in",result:n,enumArg:{index:1,source:"lists"}},
            ListAmount:{prefix:"amount of",infix:"in",result:n,enumArg:{index:1,source:"lists"}},
            ListLength:{prefix:"length of",result:n,enumArg:{index:0,source:"lists"}},
            ListContains:{infix:"contains",result:b,enumArg:{index:0,source:"lists"}},
            ListItemExists:{prefix:"item",infix:"exists in",result:b,enumArg:{index:1,source:"lists"},oneBased:[0]},
            ListIsEmpty:{prefix:"is",suffix:"empty?",result:b,enumArg:{index:0,source:"lists"}},
            ListAsJson:{suffix:"as JSON",result:t,enumArg:{index:0,source:"lists"}},
            DictValue:{prefix:"value",infix:"in",result:t,enumArg:{index:1,source:"dicts"}},
            DictHasKey:{infix:"has key",result:b,enumArg:{index:0,source:"dicts"}},
            DictSize:{prefix:"size of",result:n,enumArg:{index:0,source:"dicts"}},
            DictKeys:{prefix:"keys of",result:t,enumArg:{index:0,source:"dicts"}},
            DictAsJson:{suffix:"as JSON",result:t,enumArg:{index:0,source:"dicts"}},
            DictIsEmpty:{prefix:"is",suffix:"empty?",result:b,enumArg:{index:0,source:"dicts"}}
        };
    }

    function operator(op) { return (op && operators[op]) || null; }
    function isBoolOp(op) { const s = operator(op); return !!s && s.result === "bool"; }

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
        const p={WhenRan:"play",WhenBatteryDischargedTo:"battery-warning",WhenBatteryChargedTo:"battery-charging",WhenTime:"clock",WhenPowerPluggedIn:"plug-zap",WhenPowerUnplugged:"unplug",WhenClipboardChanged:"clipboard-check",Wait:"clock",Text:"text-cursor",Key:"keyboard",Button:"mouse-pointer-click",MoveMouse:"move",Scroll:"mouse",Command:"terminal",OpenApp:"app-window",CloseApp:"square-x",SetVariable:"equal",ChangeVariable:"trending-up",SetClipboard:"clipboard",AddToList:"plus",DeleteOfList:"trash",DeleteAllOfList:"trash",ShiftList:"arrow-left",InsertIntoList:"plus",ReplaceItemOfList:"repeat",ReverseList:"rotate",Return:"undo",If:"git-branch",IfElse:"git-fork",Repeat:"repeat",Forever:"infinity",While:"rotate",EscapeLoop:"log-out",ContinueLoop:"skip-forward",BlockHeader:"blocks",CallBlock:"blocks",BranchCallBlock:"blocks",RunBranch:"git-branch"};
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
        if (ins.type === "CallBlock" && defs) {
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
