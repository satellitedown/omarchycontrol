import QtQuick
import Quickshell
import Quickshell.Wayland
import "OverviewModel.js" as Model
PanelWindow {
    id: panel
    required property var controller
    required property var theme
    screen: controller.targetScreen
    visible: controller.opened
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "omarchycontrol"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: controller.opened ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    color: "transparent"
    property bool dragging: false
    property bool dragCanceled: false
    function cancelDrag() {
        dragCanceled = true;
        dragVisual.Drag.cancel();
        dragging = false;
        dragVisual.address = "";
    }
    function moveDrag(card, x, y) {
        if (!dragging) return;
        const point = card.mapToItem(surface, x, y);
        dragVisual.x = point.x - dragVisual.width / 2;
        dragVisual.y = point.y - dragVisual.height / 2;
        strip.edgeScroll(point.x, point.y);
    }
    function indexOf(model, role, value) {
        for (let i = 0; i < model.count; i++) if (model.get(i)[role] === value) return i;
        return -1;
    }
    function select(kind, index) {
        const c = controller;
        if (kind === "workspace" && c.workspaceModel.count) {
            c.selectionKind = kind;
            c.selectedWorkspaceId = c.workspaceModel.get(Math.max(0, Math.min(index, c.workspaceModel.count - 1))).workspaceId;
        } else if (kind === "window" && c.windowModel.count) {
            c.selectionKind = kind;
            c.selectedAddress = c.windowModel.get(Math.max(0, Math.min(index, c.windowModel.count - 1))).address;
        }
    }
    function key(event) {
        const c = controller;
        const nw = c.workspaceModel.count, nc = c.windowModel.count;
        let index = c.selectionKind === "window" ? indexOf(c.windowModel,"address",c.selectedAddress) : indexOf(c.workspaceModel,"workspaceId",c.selectedWorkspaceId);
        if (event.key === Qt.Key_Escape) {
            if (dragging) cancelDrag(); else c.hide();
        } else if (dragging) {
            return;
        } else if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
            const total = nw + nc;
            if (total) {
                const direction = event.key === Qt.Key_Backtab || (event.modifiers & Qt.ShiftModifier) ? -1 : 1;
                const next = ((c.selectionKind === "window" ? nw : 0) + Math.max(0,index) + direction + total) % total;
                select(next < nw ? "workspace" : "window", next < nw ? next : next - nw);
            }
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            if (c.selectionKind === "window") c.activateWindow(c.selectedAddress);
            else c.activateWorkspace(c.selectedWorkspaceId);
        } else if ([Qt.Key_Left,Qt.Key_Right,Qt.Key_Up,Qt.Key_Down].indexOf(event.key) >= 0) {
            if (c.selectionKind === "workspace") {
                if (event.key === Qt.Key_Down && nc) select("window",0);
                else if (event.key === Qt.Key_Left || event.key === Qt.Key_Right) select("workspace",index+(event.key === Qt.Key_Left?-1:1));
            } else {
                const next = Model.neighbor(grid.layout, index,
                    event.key === Qt.Key_Left ? -1 : event.key === Qt.Key_Right ? 1 : 0,
                    event.key === Qt.Key_Up ? -1 : event.key === Qt.Key_Down ? 1 : 0);
                if (next >= 0) select("window", next);
                else if (event.key === Qt.Key_Up && c.targetMonitor && c.targetMonitor.activeWorkspace)
                    select("workspace", indexOf(c.workspaceModel,"workspaceId",c.targetMonitor.activeWorkspace.id));
            }
        } else return;
        event.accepted = true;
    }
    Connections { target: panel.controller; function onCancelDrag() { panel.cancelDrag() } }
    Item {
        id: surface
        objectName: "overviewSurface"
        anchors.fill: parent
        focus: true
        Component.onCompleted: forceActiveFocus()
        Keys.onPressed: event => panel.key(event)
        Rectangle { anchors.fill: parent; color: Qt.alpha(panel.theme.background, 0.94) }
        MouseArea { anchors.fill: parent; onClicked: { if (panel.dragging) panel.cancelDrag(); else panel.controller.hide() } }
        Item {
            id: content
            anchors.fill: parent
            opacity: 0; scale: 0.97
            Component.onCompleted: entrance.start()
            ParallelAnimation {
                id: entrance
                NumberAnimation { target: content; property: "opacity"; to: 1; duration: 150 }
                NumberAnimation { target: content; property: "scale"; to: 1; duration: 150; easing.type: Easing.OutCubic }
            }
            WorkspaceStrip {
                id: strip
                x: 32; y: 32; width: parent.width - 64
                height: Math.max(112,Math.min(180,parent.height*0.16))
                controller: panel.controller; theme: panel.theme
                dragSource: dragVisual; dragActive: panel.dragging
                onMoveRequested: (address, workspaceId) => panel.controller.moveWindow(address,workspaceId)
            }
            Item {
                id: grid
                x: 32; y: strip.y + strip.height + 24
                width: Math.max(0,parent.width - 64); height: Math.max(0,parent.height - y - 64)
                // Only geometry/membership changes repack; title/focus updates do not.
                readonly property string geometryKey: {
                    const revision = panel.controller.revision;
                    const rows = panel.controller.windowModel;
                    const windows = [];
                    for (let i = 0; i < rows.count; ++i) {
                        const row = rows.get(i);
                        const ipc = row.toplevel ? row.toplevel.lastIpcObject : {};
                        windows.push({ address: row.address, at: ipc.at, size: ipc.size });
                    }
                    return JSON.stringify(windows);
                }
                readonly property var layout: Model.windowLayout(JSON.parse(geometryKey), width, height, {
                    x: panel.controller.targetMonitor ? panel.controller.targetMonitor.x : 0,
                    y: panel.controller.targetMonitor ? panel.controller.targetMonitor.y : 0,
                    width: panel.width, height: panel.height
                })
                Repeater {
                    model: panel.controller.windowModel
                    delegate: WindowCard {
                        id: card
                        required property int index
                        required property var model
                        readonly property var cell: grid.layout[index] || ({ x: 0, y: 0, width: 0, height: 0, chromeScale: 1 })
                        x: cell.x; y: cell.y; width: cell.width; height: cell.height
                        chromeScale: cell.chromeScale
                        controller: panel.controller; theme: panel.theme
                        address: model.address; toplevel: model.toplevel
                        selected: panel.controller.selectionKind === "window" && panel.controller.selectedAddress === address
                        onActivated: panel.controller.activateWindow(address)
                        onDragStarted: (x,y) => {
                            panel.dragCanceled = false;
                            dragVisual.address = address;
                            panel.dragging = true;
                            panel.moveDrag(card,x,y);
                        }
                        onDragMoved: (x,y) => panel.moveDrag(card,x,y)
                        onDragFinished: {
                            if (panel.dragging && !panel.dragCanceled) dragVisual.Drag.drop();
                            panel.cancelDrag();
                        }
                    }
                }
                Text { anchors.centerIn: parent; visible: panel.controller.windowModel.count === 0; text: "No windows on this desktop"; color: panel.theme.foreground; font.pixelSize: 24 }
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter; anchors.bottom: parent.bottom; anchors.bottomMargin: 22
                text: panel.controller.errorMessage || "Select a window · Drag to another desktop · Esc to cancel"
                textFormat: Text.PlainText; color: panel.theme.foreground; font.pixelSize: 14
            }
        }
        Rectangle {
            id: dragVisual
            objectName: "dragVisual"
            property string address: ""
            z: 100; width: 240; height: 160
            visible: panel.dragging
            color: panel.theme.background; radius: 8
            border.color: panel.theme.accent; border.width: 3
            Drag.active: panel.dragging
            Drag.source: dragVisual
            Drag.keys: ["omarchycontrol-window"]
            Drag.supportedActions: Qt.MoveAction
            Drag.hotSpot.x: width / 2; Drag.hotSpot.y: height / 2
            WindowPreview { anchors.fill: parent; anchors.margins: 5; toplevel: panel.controller.findWindow(dragVisual.address); enabled: panel.dragging; live: true }
        }
    }
}
