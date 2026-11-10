import QtQuick
import QtTest
import com.blockworked.Blockstitch 1.0

Item {
    id: scene
    width: 1200; height: 800
    property var observedSource: null
    property var sourceAdjustments: []
    readonly property real sourceAdjustment: observedSource ? observedSource.mouthAdjustment(0) : 0
    onSourceAdjustmentChanged: sourceAdjustments = sourceAdjustments.concat([sourceAdjustment])
    Component {
        id: setupComponent
        Item {
            id: setup
            width: 1000; height: 700
            property alias canvas: canvas
            property alias controller: controller
            property var edits: []
            property var reply: null
            BlockCanvas { id: canvas; anchors.fill: parent }
            PaletteDragController {
                id: controller
                anchors.fill: parent
                canvas: canvas
                documentId: "macro"
                document: ({strands:canvas.strands, values:canvas.floatingValues})
                submit: function(edit, done) { setup.edits.push(edit); setup.reply = done; }
            }
        }
    }
    TestCase {
        id: test
        name: "DropHandoff"
        when: windowShown
        property var watchedCanvas: null
        property var expected: null
        property string watchedId: ""
        property var misses: []
        FrameAnimation {
            running: !!test.watchedCanvas
            onTriggered: {
                const block = test.watchedCanvas.findBlockItem(test.watchedCanvas, test.watchedId);
                if (!block || block.opacity === 0) return;
                const p = block.mapToItem(null, 0, 0);
                if (Math.abs(p.x - test.expected.x) > 1 || Math.abs(p.y - test.expected.y) > 1)
                    test.misses.push({x:p.x,y:p.y,expected:test.expected,resizeX:test.watchedCanvas._resizeViewX});
            }
        }
        function all(object) {
            let found = [object];
            for (const child of object.children || []) found = found.concat(all(child));
            return found;
        }
        function instruction(id) { return {id:id,type:"Wait",duration:{kind:"Number",value:100}}; }
        function cleanup() { watchedCanvas = null; expected = null; misses = []; scene.observedSource = null; }
        function test_attach_does_not_animate_the_preview_gap_twice_data() {
            return [{tag:"canvas",palette:false},{tag:"palette",palette:true}];
        }
        function test_attach_does_not_animate_the_preview_gap_twice(data) {
            const setup = createTemporaryObject(setupComponent, scene);
            const canvas = setup.canvas;
            const head = instruction("head"), tail = instruction("tail"), moved = instruction("moved");
            canvas.strands = [{id:"target",x:0,y:0,instructions:[head,tail]}];
            if (!data.palette) canvas.strands = canvas.strands.concat([{id:"source",x:300,y:0,instructions:[moved]}]);
            wait(40);
            const target = canvas.findBlockItem(canvas,"tail");
            const destination = target.mapToItem(null,0,0);
            canvas.applySnap({targetId:"target",path:[{index:1}],x:canvas.originOffsetX,y:canvas.originOffsetY+50},200,58,false);
            wait(180);
            if (data.palette) canvas.settlePaletteDrop();
            else {
                const state = canvas.branchDragState;
                state.settleStrandId = "source"; state.settlePath = [{index:0}]; state.settling = true;
                canvas.armSettle();
            }
            canvas.strands = [{id:"target",x:0,y:0,instructions:[head,moved,tail]}];
            const attached = canvas.findBlockItem(canvas,"moved");
            const following = canvas.findBlockItem(canvas,"tail");
            waitForRendering(canvas);
            fuzzyCompare(attached.mapToItem(null,0,0).y,destination.y,1,"attached block starts at the opened gap");
            fuzzyCompare(following.mapToItem(null,0,0).y,destination.y+50,1,"following block keeps its preview position");
            watchedCanvas = canvas; watchedId = "moved"; expected = destination;
            wait(180);
            compare(misses,[],"document confirmation must not replay the gap animation");
        }
        function test_gap_adjustments_ease_in_and_out() {
            const previousScale = Motion.durationScale;
            Motion.durationScale = 4;
            try {
                const setup = createTemporaryObject(setupComponent, scene);
                const canvas = setup.canvas;
                canvas.strands = [{id:"target",x:0,y:0,instructions:[instruction("target-block")]}];
                wait(40);
                const block = canvas.findBlockItem(canvas,"target-block");
                canvas.applySnap({targetId:"target",path:[{index:0}],x:0,y:0},200,58,false);
                compare(block.snapShift,50);
                verify(block.displayedSnapShift < 50);
                tryVerify(() => block.displayedSnapShift > 0 && block.displayedSnapShift < 50);
                tryCompare(block,"displayedSnapShift",50);
                canvas.clearSnap();
                verify(block.displayedSnapShift > 0);
                tryCompare(block,"displayedSnapShift",0);
            } finally {
                Motion.durationScale = previousScale;
            }
        }
        function test_container_adjustments_ease() {
            const previousScale = Motion.durationScale;
            // Observe an actual intermediate value rather than assuming that
            // a busy CI runner presents a frame exactly 60 ms after the edit.
            Motion.durationScale = 4;
            try {
                const setup = createTemporaryObject(setupComponent, scene);
                const canvas = setup.canvas;
                canvas.strands = [{id:"target",x:0,y:0,instructions:[{id:"wrap",type:"If",condition:{kind:"Bool"},body:[]}]}];
                wait(40);
                const block = canvas.findBlockItem(canvas,"wrap");
                const initial = block.effMouthHeights[0];
                canvas.applySnap({targetId:"target",path:[{index:0,slot:0},{index:0}],x:0,y:0,empty:true},200,58,false);
                tryVerify(() => block.effMouthHeights[0] > initial && block.effMouthHeights[0] < 50);
                tryVerify(() => Math.abs(block.effMouthHeights[0] - 50) < 0.01);
                canvas.clearSnap();
                verify(block.effMouthHeights[0] > initial);
                tryVerify(() => Math.abs(block.effMouthHeights[0] - initial) < 0.01);
            } finally {
                Motion.durationScale = previousScale;
            }
        }
        function test_drag_stays_under_pointer_during_layout_data() {
            const rows = [];
            for (const zoom of [0.5, 1, 1.8])
                for (const nested of [false, true])
                    rows.push({tag:zoom + (nested ? "_else-branch" : "_following-wrap"),zoom:zoom,nested:nested});
            return rows;
        }
        function test_drag_stays_under_pointer_during_layout(data) {
            const setup = createTemporaryObject(setupComponent, scene);
            const canvas = setup.canvas;
            canvas.externalDragPreview = false;
            const moved = instruction("moved"), follower = instruction("follower");
            const wrap = {id:"wrap",type:"IfElse",then_body:[],else_body:data.nested ? [moved,follower] : []};
            canvas.strands = [{id:"source",x:40,y:40,instructions:data.nested ? [wrap] : [wrap,moved,follower]}];
            wait(40);
            canvas.setZoom(data.zoom);
            const block = canvas.findBlockItem(canvas,"moved");
            const outer = canvas.findBlockItem(canvas,"wrap");
            const start = block.mapToItem(null,10,10);
            const path = data.nested ? [{index:0,slot:1},{index:0}] : [{index:1}];
            canvas.beginDrag("source",path,2,start.x,start.y,10,10,block.width,block.height);
            const destination = outer.mapToItem(null,outer.spine,outer.headHeight);
            canvas.moveDrag(destination.x+10*data.zoom,destination.y+10*data.zoom);
            verify(canvas.branchDragState.snapValid);
            compare(canvas.branchDragState.snapPath,[{index:0,slot:0},{index:0}]);
            const following = canvas.findBlockItem(canvas,"follower");
            for (let i = 0; i < 12; ++i) {
                const position = block.mapToItem(null,0,0);
                fuzzyCompare(position.x,destination.x,1,"dragged block x stays under the pointer");
                fuzzyCompare(position.y,destination.y,1,"dragged block y stays under the pointer");
                fuzzyCompare(following.mapToItem(null,0,0).y,destination.y+50*data.zoom,1,"tail keeps its spacing");
                wait(20);
            }
            canvas.cancelDrag();
        }
        function test_nested_drop_keeps_preview_position_data() {
            return [{tag:"detach",attach:false},{tag:"attach",attach:true}];
        }
        function test_nested_drop_keeps_preview_position(data) {
            const setup = createTemporaryObject(setupComponent, scene);
            const canvas = setup.canvas;
            const moved = instruction("moved"), wrap = {id:"wrap",type:"IfElse",then_body:[],else_body:[moved]};
            canvas.strands = [{id:"source",x:40,y:40,instructions:[wrap]}];
            wait(40);
            const block = canvas.findBlockItem(canvas,"moved");
            const outer = canvas.findBlockItem(canvas,"wrap");
            const start = block.mapToItem(null,10,10);
            const path = [{index:0,slot:1},{index:0}];
            canvas.beginDrag("source",path,1,start.x,start.y,10,10,block.width,block.height);
            const attachPoint = outer.mapToItem(null,outer.spine,outer.headHeight);
            canvas.moveDrag(attachPoint.x+10,attachPoint.y+10);
            wait(180);
            const destination = data.attach ? attachPoint : canvas.mapToItem(null,650,300);
            canvas.moveDrag(destination.x+10,destination.y+10);
            compare(canvas.branchDragState.snapValid,data.attach);
            canvas.endDrag(destination.x+10,destination.y+10);
            for (let i = 0; i < 10; ++i) {
                const position = block.mapToItem(null,0,0);
                fuzzyCompare(position.x,destination.x,1,"drop x while the layout settles");
                fuzzyCompare(position.y,destination.y,1,"drop y while the layout settles");
                wait(20);
            }
            const at = canvas.workspacePoint(destination.x,destination.y);
            const updated = {id:"wrap",type:"IfElse",then_body:data.attach ? [moved] : [],else_body:[]};
            canvas.strands = [{id:"source",x:40,y:40,instructions:[updated]}];
            if (!data.attach)
                canvas.strands = canvas.strands.concat([{id:"detached",x:Math.round(at.x),y:Math.round(at.y),instructions:[moved]}]);
            wait(180);
            const landed = canvas.findBlockItem(canvas,"moved").mapToItem(null,0,0);
            fuzzyCompare(landed.x,destination.x,1,"confirmed x");
            fuzzyCompare(landed.y,destination.y,1,"confirmed y");
            const timeout = Array.from(canvas.dropSettle.resources).find(o => o.interval !== undefined);
            verify(!!timeout);
            compare(timeout.running,false,"document confirmation must stop the settle timeout");
        }
        function test_release_preserves_source_collapse_data() {
            return [{tag:"detach",attach:false},{tag:"attach",attach:true}];
        }
        function test_release_preserves_source_collapse(data) {
            const setup = createTemporaryObject(setupComponent, scene);
            const canvas = setup.canvas;
            canvas.strands = [{id:"source",x:40,y:40,instructions:[{id:"wrap",type:"If",body:[instruction("moved")]}]},
                {id:"target",x:400,y:40,instructions:[instruction("target-block")]}];
            wait(40);
            const block = canvas.findBlockItem(canvas,"moved");
            const start = block.mapToItem(null,10,10);
            canvas.beginDrag("source",[{index:0,slot:0},{index:0}],1,start.x,start.y,10,10,block.width,block.height);
            const target = canvas.findBlockItem(canvas,"target-block");
            const destination = data.attach ? target.mapToItem(null,0,50) : canvas.mapToItem(null,600,300);
            canvas.moveDrag(destination.x+10,destination.y+10);
            compare(canvas.branchDragState.snapValid,data.attach);
            scene.observedSource = canvas.findBlockItem(canvas,"wrap");
            compare(scene.sourceAdjustment,-24);
            scene.sourceAdjustments = [];
            canvas.endDrag(destination.x+10,destination.y+10);
            compare(scene.sourceAdjustments,[],"release must not briefly reopen the source branch");
        }
        function test_detach_confirmation_does_not_reopen_source_data() {
            return [{tag:"immediate",delay:0}, {tag:"mid-collapse",delay:40}, {tag:"collapsed",delay:180}];
        }
        function test_detach_confirmation_does_not_reopen_source(data) {
            const setup = createTemporaryObject(setupComponent, scene);
            const canvas = setup.canvas;
            const moved = instruction("moved");
            canvas.strands = [{id:"source",x:40,y:40,instructions:[
                {id:"wrap",type:"IfElse",then_body:[moved],else_body:[]}
            ]}];
            wait(40);
            const block = canvas.findBlockItem(canvas,"moved");
            const outer = canvas.findBlockItem(canvas,"wrap");
            const start = block.mapToItem(null,10,10);
            const destination = canvas.mapToItem(null,600,300);
            canvas.beginDrag("source",[{index:0,slot:0},{index:0}],1,start.x,start.y,10,10,block.width,block.height);
            canvas.moveDrag(destination.x+10,destination.y+10);
            wait(data.delay);
            canvas.endDrag(destination.x+10,destination.y+10);
            const at = canvas.workspacePoint(destination.x,destination.y);
            let previous = outer.effMouthHeights[0];
            canvas.strands = [{id:"source",x:40,y:40,instructions:[
                {id:"wrap",type:"IfElse",then_body:[],else_body:[]}
            ]},{id:"detached",x:Math.round(at.x),y:Math.round(at.y),instructions:[moved]}];
            waitForRendering(canvas);
            const surface = all(outer).find(o => o.outlinePath !== undefined);
            const writer = surface.writer(); surface.trace(writer);
            compare(surface.outlinePath,writer.text(),"first rendered frame must draw the collapsed branch geometry");
            for (let i = 0; i < 12; ++i) {
                wait(20);
                const height = outer.effMouthHeights[0];
                verify(height <= previous + 0.1,"source reopened from " + previous + " to " + height);
                previous = height;
            }
            compare(outer.effMouthHeights[0],26);
        }
        function test_detached_block_keeps_outline_during_confirmation_data() {
            return [{tag:"stationary",moveAway:false},{tag:"moved-away",moveAway:true}];
        }
        function test_detached_block_keeps_outline_during_confirmation(data) {
            const setup = createTemporaryObject(setupComponent, scene);
            const canvas = setup.canvas;
            const moved = instruction("moved");
            canvas.strands = [{id:"source",x:40,y:40,instructions:[{id:"wrap",type:"If",body:[moved]}]}];
            wait(40);
            const block = canvas.findBlockItem(canvas,"moved");
            const start = block.mapToItem(null,10,25);
            const destination = canvas.mapToItem(null,600,300);
            canvas.beginDrag("source",[{index:0,slot:0},{index:0}],1,start.x,start.y,10,25,block.width,block.height);
            canvas.moveDrag(destination.x+10,destination.y+25);
            mouseMove(scene,destination.x+10,destination.y+25);
            canvas.endDrag(destination.x+10,destination.y+25);
            if (data.moveAway)
                mouseMove(scene,900,600);
            const at = canvas.workspacePoint(destination.x,destination.y);
            canvas.strands = [{id:"source",x:40,y:40,instructions:[{id:"wrap",type:"If",body:[]}]},
                {id:"detached",x:Math.round(at.x),y:Math.round(at.y),instructions:[moved]}];
            const landed = canvas.findBlockItem(canvas,"moved");
            const surface = all(landed).find(o => o.outlinePath !== undefined);
            waitForRendering(canvas);
            compare(surface.hovered,!data.moveAway,"the first frame must reflect the pointer position");
            const image = grabImage(setup);
            const position = landed.mapToItem(setup,0,0);
            const color = image.pixel(Math.round(position.x),Math.round(position.y+25));
            if (!data.moveAway)
                verify(color.b - color.r > 0.4,"first rendered frame must show the hover outline: " + color);
            mouseMove(scene,900,600);
            tryCompare(surface,"hovered",false);
        }
        function test_canvas_resize_during_drag() {
            const setup = createTemporaryObject(setupComponent, scene);
            const canvas = setup.canvas;
            canvas.strands = [{id:"source",x:40,y:40,instructions:[instruction("moved")]}];
            wait(40);
            canvas.setZoom(0.5);
            const block = canvas.findBlockItem(canvas,"moved");
            const start = block.mapToItem(null,10,10);
            const destination = canvas.mapToItem(null,300,100);
            canvas.beginDrag("source",[{index:0}],1,start.x,start.y,10,10,block.width,block.height);
            canvas.moveDrag(destination.x+5,destination.y+5);
            canvas.strands = canvas.strands.concat([{id:"distant",x:2000,y:1600,instructions:[instruction("other")]}]);
            wait(40);
            canvas.moveDrag(destination.x+5,destination.y+5);
            canvas.endDrag(destination.x+5,destination.y+5);
            const landed = block.mapToItem(null,0,0);
            fuzzyCompare(landed.x,destination.x,1,"handoff x after resize");
            fuzzyCompare(landed.y,destination.y,1,"handoff y after resize");
        }
        function test_snap_gap_resize_during_drag() {
            const setup = createTemporaryObject(setupComponent, scene);
            const canvas = setup.canvas;
            canvas.strands = [{id:"source",x:300,y:600,instructions:[instruction("moved")]},
                {id:"target",x:0,y:700,instructions:[{id:"wrap",type:"If",condition:{kind:"Bool"},body:[instruction("child")]}]}];
            wait(40);
            canvas.setZoom(0.5);
            const block = canvas.findBlockItem(canvas,"moved");
            canvas.revealInstruction("child");
            wait(400);
            const child = canvas.findBlockItem(canvas,"child");
            const start = block.mapToItem(null,10,10);
            const destination = child.mapToItem(null,0,child.height-8);
            canvas.beginDrag("source",[{index:0}],1,start.x,start.y,10,10,block.width,block.height);
            canvas.moveDrag(destination.x+5,destination.y+5);
            verify(canvas.paletteSnapValid);
            wait(40);
            const landing = canvas.paletteDropScenePoint();
            canvas.endDrag(destination.x+5,destination.y+5);
            const landed = block.mapToItem(null,0,0);
            fuzzyCompare(landed.x,landing.x,1,"snap handoff x");
            fuzzyCompare(landed.y,landing.y,1,"snap handoff y");
        }
        function test_release_to_document_data() {
            const rows = [];
            for (const zoom of [0.5, 1, 1.8])
                for (const palette of [false, true])
                    for (const edge of [false, true])
                        rows.push({tag: zoom + "_" + (palette ? "palette" : "canvas") + "_" + (edge ? "left" : "center"),
                            zoom:zoom, palette:palette, edge:edge});
            return rows;
        }
        function test_release_to_document(data) {
            const setup = createTemporaryObject(setupComponent, scene);
            const canvas = setup.canvas, controller = setup.controller;
            canvas.strands = [{id:"source",x:40,y:40,instructions:[instruction("moved")]}];
            wait(40);
            canvas.setZoom(data.zoom);
            const flick = all(canvas).find(o => o.contentX !== undefined && o.contentWidth !== undefined);
            if (data.edge) flick.contentX = 0;
            const offset = 10 * data.zoom;
            const destination = canvas.mapToItem(null, data.edge ? 8 : 300, 100);
            if (data.palette) {
                controller.begin({kind:"instruction",instruction:instruction("palette")}, 900, 600, 10, 10);
                controller.move(destination.x + offset, destination.y + offset);
                controller.end(destination.x + offset, destination.y + offset);
                const edit = setup.edits[0];
                verify(!!edit);
                watchedId = edit.instruction.id;
                expected = destination;
                watchedCanvas = canvas;
                wait(30);
                canvas.strands = canvas.strands.concat([{id:"added",x:edit.x,y:edit.y,instructions:[edit.instruction]}]);
                const first = canvas.findBlockItem(canvas, watchedId);
                verify(!!first);
                const initial = first.mapToItem(null,0,0);
                fuzzyCompare(initial.x,destination.x,1,"first layout x");
                fuzzyCompare(initial.y,destination.y,1,"first layout y");
                wait(30);
                setup.reply(true);
            } else {
                const block = canvas.findBlockItem(canvas,"moved");
                const start = block.mapToItem(null,10,10);
                canvas.beginDrag("source",[{index:0}],1,start.x,start.y,10,10,block.width,block.height);
                canvas.moveDrag(destination.x + offset,destination.y + offset);
                canvas.endDrag(destination.x + offset,destination.y + offset);
                watchedId = "moved"; expected = destination; watchedCanvas = canvas;
                wait(30);
                const at = canvas.workspacePoint(destination.x,destination.y);
                canvas.strands = [{id:"source",x:Math.round(at.x),y:Math.round(at.y),instructions:[instruction("moved")]}];
            }
            wait(150);
            watchedCanvas = null;
            compare(misses, [], "every rendered frame stays at the drop point");
        }
    }
}
