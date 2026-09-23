import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import "OverviewModel.js" as Model
PanelWindow {
    id: panel
    required property var controller
    required property var theme
    screen: controller.targetScreen
    visible: controller.opened

    // Decode the wallpaper at the output's physical resolution, resolved
    // before first use. A size that changes when the layer maps restarts
    // decoding and stalls the entrance on a fresh frame. The long edge is
    // capped because the compositor re-decodes on every mapping, and a
    // full 3840x2160 PNG costs ~150 ms while staying visually identical
    // behind the dim overlay.
    readonly property int wallpaperDecodeLimit: 2560
    property size wallpaperDecodeSize: Qt.size(0, 0)
    function syncWallpaperDecodeSize() {
        const monitor = panel.controller.targetMonitor || Hyprland.focusedMonitor;
        if (!monitor || !(monitor.width > 0) || !(monitor.height > 0))
            return;
        const longest = Math.max(monitor.width, monitor.height);
        const scale = Math.min(1, wallpaperDecodeLimit / longest);
        const width = Math.max(1, Math.round(monitor.width * scale));
        const height = Math.max(1, Math.round(monitor.height * scale));
        if (width !== wallpaperDecodeSize.width || height !== wallpaperDecodeSize.height)
            wallpaperDecodeSize = Qt.size(width, height);
    }
    Component.onCompleted: syncWallpaperDecodeSize()
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
        if (c.closing) { event.accepted = true; return; }
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
    Connections {
        target: panel.controller
        function onCancelDrag() { panel.cancelDrag() }
        function onCloseRequested() { surface.close() }
        function onOpenedChanged() { if (panel.controller.opened) surface.open() }
    }
    Item {
        id: surface
        objectName: "overviewSurface"
        anchors.fill: parent
        focus: true
        property real entranceProgress: 0
        property bool entranceStarted: false
        property real chromeProgress: 0
        property bool framesReady: false
        property int warmFrames: 0
        // Readiness is the decoded image, not the symlink lookup. Waiting on
        // that process added ~100 ms of dead time before every entrance.
        readonly property bool wallpaperReady: wallpaper.status === Image.Ready
            || wallpaper.status === Image.Error
            || !String(panel.theme.wallpaperSource).length
        readonly property bool sceneReady: framesReady && wallpaperReady
        function startEntrance() {
            if (entranceStarted || panel.controller.closing) return;
            entranceStarted = true;
            captureDeadline.stop();
            entrance.start();
            // Chrome uses the same reveal, so nothing is drawn over the live
            // desktop while the layer surface is still producing its first frame.
            chromeAnimation.start();
        }
        function close() {
            captureDeadline.stop();
            entrance.stop();
            chromeAnimation.stop();
            if (entranceProgress === 0) {
                Qt.callLater(panel.controller.finishClose);
                return;
            }
            entrance.to = 0;
            entrance.duration = Math.max(80, 240 * entranceProgress);
            chromeAnimation.to = 0;
            chromeAnimation.duration = entrance.duration;
            chromeAnimation.start();
            entrance.start();
        }
        function tryStartEntrance() {
            if (entranceStarted || !cards.count) return;
            for (let i = 0; i < cards.count; ++i) {
                const card = cards.itemAt(i);
                if (!card || !card.previewReady || card.width <= 0 || card.height <= 0) return;
            }
            framesReady = true;
        }
        function open() {
            panel.syncWallpaperDecodeSize();
            entrance.stop();
            chromeAnimation.stop();
            entranceProgress = 0;
            chromeProgress = 0;
            entranceStarted = false;
            framesReady = false;
            warmFrames = 0;
            entrance.to = 1;
            entrance.duration = 300;
            chromeAnimation.to = 1;
            chromeAnimation.duration = 160;
            forceActiveFocus();
            if (panel.controller.closing) { close(); return; }
            captureDeadline.start();
            Qt.callLater(tryStartEntrance);
        }
        Component.onCompleted: if (panel.controller.opened) open()
        // Render the prepared scene at desktop positions before moving it.
        // hasContent precedes GPU import; hidden/zero-opacity items stay cold.
        FrameAnimation {
            running: panel.controller.opened && !surface.entranceStarted && !panel.controller.closing
            onTriggered: {
                if (surface.sceneReady && ++surface.warmFrames >= 2)
                    surface.startEntrance();
            }
        }
        // Unavailable captures must not stall the overview. Wallpaper decoding
        // is gated separately: never substitute a gray frame while it loads.
        Timer { id: captureDeadline; interval: 80; onTriggered: surface.framesReady = true }
        NumberAnimation {
            id: entrance
            target: surface; property: "entranceProgress"
            to: 1; duration: 300; easing.type: Easing.InOutCubic
            onFinished: if (panel.controller.closing) Qt.callLater(panel.controller.finishClose)
        }
        NumberAnimation {
            id: chromeAnimation
            target: surface; property: "chromeProgress"
            to: 1; duration: 160; easing.type: Easing.OutCubic
        }
        Keys.onPressed: event => panel.key(event)
        // The container stays visible so the decoded wallpaper is never
        // released; hiding an Image makes it reload and re-decode on the next
        // opening, which stalled the entrance for ~300 ms.
        Item {
            anchors.fill: parent
            readonly property real shown: surface.sceneReady || surface.entranceStarted ? 1 : 0
            Rectangle { anchors.fill: parent; color: panel.theme.background; opacity: parent.shown }
            Image {
                id: wallpaper
                anchors.fill: parent
                source: panel.theme.wallpaperSource
                sourceSize: panel.wallpaperDecodeSize
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                cache: true
                opacity: parent.shown
            }
            // Dim the wallpaper as the windows settle, without a blur pass.
            Rectangle { anchors.fill: parent; color: "#26000000"; opacity: surface.entranceProgress }
        }
        MouseArea { anchors.fill: parent; onClicked: { if (panel.dragging) panel.cancelDrag(); else panel.controller.hide() } }
        Item {
            id: content
            anchors.fill: parent
            Rectangle {
                z: 2; opacity: surface.chromeProgress
                width: parent.width
                height: strip.y + strip.height + 18
                color: "#66000000"
                Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: "#18ffffff" }
            }
            WorkspaceStrip {
                id: strip
                z: 3; opacity: surface.chromeProgress
                transform: Translate { y: -16 * (1 - surface.chromeProgress) }
                x: 40; y: 24; width: Math.max(0, parent.width - 80)
                height: Math.max(112,Math.min(164,parent.height*0.125))
                controller: panel.controller; theme: panel.theme
                dragSource: dragVisual; dragActive: panel.dragging
                onMoveRequested: (address, workspaceId) => panel.controller.moveWindow(address,workspaceId)
            }
            Item {
                id: grid
                x: 40; y: strip.y + strip.height + 42
                width: Math.max(0,parent.width - 80); height: Math.max(0,parent.height - y - 64)
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
                    id: cards
                    onItemAdded: Qt.callLater(surface.tryStartEntrance)
                    model: panel.controller.windowModel
                    delegate: WindowCard {
                        id: card
                        required property int index
                        required property var model
                        readonly property var cell: grid.layout[index] || ({ x: 0, y: 0, width: 0, height: 0, chromeScale: 1 })
                        x: cell.x; y: cell.y; width: cell.width; height: cell.height
                        chromeScale: cell.chromeScale
                        settled: surface.entranceProgress === 1
                        readonly property bool hasOrigin: Model.hasGeometry(ipc) && width > 12 * chromeScale
                        readonly property real sourceScale: hasOrigin ? ipc.size[0] / (width - 12 * chromeScale) : 0.96
                        readonly property real sourceX: hasOrigin
                            ? ipc.at[0] - (panel.controller.targetMonitor ? panel.controller.targetMonitor.x : 0) - grid.x - x - 6 * chromeScale : 0
                        readonly property real sourceY: hasOrigin
                            ? ipc.at[1] - (panel.controller.targetMonitor ? panel.controller.targetMonitor.y : 0) - grid.y - y - 6 * chromeScale : 16
                        // Animate transforms, not layout/capture dimensions. The
                        // preview's top-left starts at the real client position.
                        transform: [
                            Scale {
                                origin.x: 6 * card.chromeScale; origin.y: 6 * card.chromeScale
                                xScale: 1 + (card.sourceScale - 1) * (1 - surface.entranceProgress)
                                yScale: xScale
                            },
                            Translate {
                                x: card.sourceX * (1 - surface.entranceProgress)
                                y: card.sourceY * (1 - surface.entranceProgress)
                            }
                        ]
                        opacity: hasOrigin ? (previewReady || surface.entranceStarted ? 1 : 0) : surface.entranceProgress
                        z: surface.entranceProgress < 1 ? -Math.max(0, Number(ipc.focusHistoryID) || 0) : 0
                        chromeOpacity: Math.max(0, (surface.entranceProgress - 0.35) / 0.65)
                        onPreviewReadyChanged: Qt.callLater(surface.tryStartEntrance)
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
                Text {
                    anchors.centerIn: parent
                    visible: panel.controller.windowModel.count === 0
                    text: "No windows on this desktop"
                    color: panel.theme.overviewText
                    font.pixelSize: 24
                    style: Text.Outline; styleColor: "#66000000"
                }
            }
            Rectangle {
                z: 3; opacity: surface.chromeProgress
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom; anchors.bottomMargin: 18
                width: Math.min(parent.width - 32, hint.implicitWidth + 28)
                height: 28; radius: 14; color: "#80000000"
                Text {
                    id: hint
                    anchors.fill: parent; anchors.leftMargin: 14; anchors.rightMargin: 14
                    text: panel.controller.errorMessage || "Select a window · Drag to another desktop · Esc to cancel"
                    textFormat: Text.PlainText
                    color: panel.controller.errorMessage ? panel.theme.overviewText : panel.theme.overviewMuted
                    font.pixelSize: 12
                    horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                    elide: Text.ElideRight
                }
            }
        }
        Rectangle {
            id: dragVisual
            objectName: "dragVisual"
            property string address: ""
            z: 100; width: 240; height: 160
            visible: panel.dragging
            color: panel.theme.background; radius: 8
            border.color: panel.theme.overviewAccent; border.width: 2
            Drag.active: panel.dragging
            Drag.source: dragVisual
            Drag.keys: ["omarchycontrol-window"]
            Drag.supportedActions: Qt.MoveAction
            Drag.hotSpot.x: width / 2; Drag.hotSpot.y: height / 2
            WindowPreview { anchors.fill: parent; anchors.margins: 5; toplevel: panel.controller.findWindow(dragVisual.address); enabled: panel.dragging; live: true }
        }
    }
}
