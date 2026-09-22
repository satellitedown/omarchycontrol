import QtQuick
import QtQuick.Controls as Controls
import "OverviewModel.js" as Model

Item {
    id: root

    required property var controller
    required property var theme
    property Item dragSource: null
    property bool dragActive: false

    signal moveRequested(string address, int workspaceId)

    objectName: "workspaceStrip"

    readonly property real screenWidth: controller.targetScreen
        ? Math.max(1, controller.targetScreen.width) : 16
    readonly property real screenHeight: controller.targetScreen
        ? Math.max(1, controller.targetScreen.height) : 9
    readonly property real monitorX: controller.targetMonitor ? controller.targetMonitor.x : 0
    readonly property real monitorY: controller.targetMonitor ? controller.targetMonitor.y : 0
    readonly property real thumbnailWidth: Math.max(0,
        Math.min(width, Math.max(0, height - 30) * screenWidth / screenHeight))
    readonly property real thumbnailHeight: thumbnailWidth * screenHeight / screenWidth
    readonly property int activeWorkspaceId: controller.targetMonitor
        && controller.targetMonitor.activeWorkspace ? controller.targetMonitor.activeWorkspace.id : 0

    property bool _dropCommitted: false
    property int _edgeDirection: 0
    property point _dragPoint: Qt.point(0, 0)

    readonly property var dropWorkspaceId: {
        // indexAt() itself has no notify signal; also observe compositor changes.
        const revision = controller.revision;
        if (!stripDrop.containsDrag || !dragWindow(stripDrop.drag.source))
            return null;
        const workspace = workspaceAt(stripDrop.drag.x, stripDrop.drag.y);
        return workspace && canDrop(stripDrop.drag.source, workspace.workspaceId)
            ? workspace.workspaceId : null;
    }

    function workspaceIndex(workspaceId) {
        for (let i = 0; i < controller.workspaceModel.count; ++i) {
            if (controller.workspaceModel.get(i).workspaceId === workspaceId)
                return i;
        }
        return -1;
    }

    function workspaceAt(x, y) {
        if (x < 0 || y < 0 || x >= desktops.width || y >= desktops.height)
            return null;
        const index = desktops.indexAt(desktops.contentX + x, desktops.contentY + y);
        return index >= 0 && index < controller.workspaceModel.count
            ? controller.workspaceModel.get(index) : null;
    }

    function dragWindow(source) {
        if (!dragActive || _dropCommitted || !controller.opened || controller.busy
                || !source || source !== dragSource || !controller.targetMonitor
                || !controller.targetMonitor.activeWorkspace)
            return null;
        const address = Model.normalizeAddress(source.address);
        if (!address || address !== source.address)
            return null;
        for (let i = 0; i < controller.windowModel.count; ++i) {
            const row = controller.windowModel.get(i);
            if (row.address === address && row.toplevel
                    && Model.windowEligible(row.toplevel.lastIpcObject,
                        controller.targetMonitor.id, controller.targetMonitor.activeWorkspace.id))
                return row.toplevel;
        }
        return null;
    }

    function canDrop(source, workspaceId) {
        const toplevel = dragWindow(source);
        return !!toplevel && workspaceIndex(workspaceId) >= 0
            && toplevel.lastIpcObject.workspace.id !== workspaceId;
    }

    function revealSelection() {
        if (dragActive || !controller.opened)
            return;
        const workspaceId = controller.selectionKind === "workspace"
            ? controller.selectedWorkspaceId : activeWorkspaceId;
        const index = workspaceIndex(workspaceId);
        if (index >= 0)
            desktops.positionViewAtIndex(index, ListView.Contain);
    }

    function edgeScroll(panelX, panelY) {
        _dragPoint = Qt.point(panelX, panelY);
        _edgeDirection = 0;
        if (!dragWindow(dragSource)
                || !dragSource.parent || desktops.contentWidth <= desktops.width)
            return;
        const point = desktops.mapFromItem(dragSource.parent, panelX, panelY);
        if (point.y < 0 || point.y >= desktops.height || point.x < 0 || point.x >= desktops.width)
            return;
        const minimum = desktops.originX;
        const maximum = minimum + Math.max(0, desktops.contentWidth - desktops.width);
        if (point.x < 24 && desktops.contentX > minimum + 1)
            _edgeDirection = -1;
        else if (point.x >= desktops.width - 24 && desktops.contentX < maximum - 1)
            _edgeDirection = 1;
    }

    onDragActiveChanged: {
        _edgeDirection = 0;
        if (dragActive) {
            _dropCommitted = false;
            desktops.cancelFlick();
        }
    }
    onWidthChanged: Qt.callLater(revealSelection)
    Component.onCompleted: Qt.callLater(revealSelection)

    Connections {
        target: root.controller
        function onSelectedWorkspaceIdChanged() { root.revealSelection(); }
        function onSelectionKindChanged() { root.revealSelection(); }
        function onBusyChanged() {
            if (root.controller.busy)
                root._edgeDirection = 0;
        }
    }

    Timer {
        interval: 16
        repeat: true
        running: root.dragActive && root._edgeDirection !== 0
        onTriggered: {
            root.edgeScroll(root._dragPoint.x, root._dragPoint.y);
            if (root._edgeDirection === 0)
                return;
            const minimum = desktops.originX;
            const maximum = minimum + Math.max(0, desktops.contentWidth - desktops.width);
            desktops.contentX = Math.max(minimum,
                Math.min(maximum, desktops.contentX + root._edgeDirection * 8));
            if (desktops.contentX <= minimum + 1 || desktops.contentX >= maximum - 1)
                root._edgeDirection = 0;
        }
    }

    ListView {
        id: desktops

        anchors.horizontalCenter: parent.horizontalCenter
        width: Math.min(root.width, count * root.thumbnailWidth + Math.max(0, count - 1) * spacing)
        height: root.height
        orientation: ListView.Horizontal
        layoutDirection: Qt.LeftToRight
        spacing: 24
        clip: true
        cacheBuffer: 0
        reuseItems: false
        boundsBehavior: Flickable.StopAtBounds
        interactive: !root.dragActive
        keyNavigationEnabled: false
        currentIndex: -1
        model: root.controller.workspaceModel

        onCountChanged: Qt.callLater(root.revealSelection)

        delegate: Item {
            id: desktop

            required property int workspaceId
            required property string label

            objectName: "workspace-" + workspaceId
            width: root.thumbnailWidth
            height: desktops.height

            readonly property bool intersectsViewport: visible && width > 0 && height > 0
                && x + width > desktops.contentX && x < desktops.contentX + desktops.width
            readonly property bool currentDesktop: workspaceId === root.activeWorkspaceId
            readonly property bool keyboardSelected: root.controller.selectionKind === "workspace"
                && workspaceId === root.controller.selectedWorkspaceId
            readonly property bool dropHighlighted: root.dropWorkspaceId === workspaceId

            property string _snapshotSignature: ""
            property string _stackingSignature: ""
            property var _snapshotRows: []
            property var _snapshotHandles: ({})
            property var _stacking: ({})

            function refreshSnapshot() {
                const rows = root.controller.windowsForWorkspace(workspaceId);
                const stacking = ({});
                const stackingAddresses = [];
                for (let i = 0; i < rows.length; ++i) {
                    stacking[rows[i].address] = i;
                    stackingAddresses.push(rows[i].address);
                }
                const stackingSignature = JSON.stringify(stackingAddresses);
                if (stackingSignature !== _stackingSignature) {
                    _stackingSignature = stackingSignature;
                    _stacking = stacking;
                }

                // Stable address order prevents a focus-only change from recapturing.
                rows.sort(function(a, b) {
                    return a.address < b.address ? -1 : a.address > b.address ? 1 : 0;
                });
                const metadata = [];
                const handles = ({});
                let handlesChanged = false;
                for (let i = 0; i < rows.length; ++i) {
                    const row = rows[i];
                    metadata.push([row.address, row.at, row.size]);
                    const previous = _snapshotHandles[row.address];
                    const wayland = row.toplevel ? row.toplevel.wayland : null;
                    handles[row.address] = { toplevel: row.toplevel, wayland: wayland };
                    if (!previous || previous.toplevel !== row.toplevel || previous.wayland !== wayland)
                        handlesChanged = true;
                }
                const signature = JSON.stringify(metadata);
                if (signature !== _snapshotSignature || handlesChanged) {
                    _snapshotSignature = signature;
                    _snapshotHandles = handles;
                    _snapshotRows = rows;
                }
            }

            function activate() {
                if (root.dragActive || root.controller.busy || root.workspaceIndex(workspaceId) < 0)
                    return;
                root.controller.selectionKind = "workspace";
                root.controller.selectedWorkspaceId = workspaceId;
                root.controller.activateWorkspace(workspaceId);
            }

            Component.onCompleted: refreshSnapshot()
            onWorkspaceIdChanged: refreshSnapshot()

            Connections {
                target: root.controller
                function onRevisionChanged() { desktop.refreshSnapshot(); }
            }

            Accessible.role: Accessible.Button
            Accessible.name: label
            Accessible.focusable: true
            Accessible.focused: keyboardSelected
            Accessible.onPressAction: activate()

            Rectangle {
                id: canvas
                width: desktop.width
                height: root.thumbnailHeight
                color: root.theme.background
                radius: 6
                clip: true

                Loader {
                    anchors.fill: parent
                    active: root.controller.opened && desktop.intersectsViewport
                    sourceComponent: Item {
                        Repeater {
                            model: desktop._snapshotRows
                            delegate: WindowPreview {
                                required property var modelData
                                toplevel: modelData.toplevel
                                live: false
                                readonly property var rect: Model.miniatureRect(modelData,
                                    root.monitorX, root.monitorY,
                                    canvas.width / root.screenWidth, canvas.height / root.screenHeight)
                                x: rect.x; y: rect.y; width: rect.width; height: rect.height
                                z: desktop._stacking[modelData.address] || 0
                                backgroundColor: root.theme.background
                                foregroundColor: root.theme.foreground
                                mutedColor: root.theme.muted
                            }
                        }
                    }
                }

                Rectangle {
                    anchors.fill: parent
                    radius: canvas.radius
                    color: desktop.dropHighlighted
                        ? Qt.rgba(root.theme.accent.r, root.theme.accent.g, root.theme.accent.b, 0.14)
                        : "transparent"
                    border.width: desktop.dropHighlighted || desktop.keyboardSelected ? 3
                        : desktop.currentDesktop || pointer.containsMouse ? 2 : 1
                    border.color: desktop.dropHighlighted || desktop.keyboardSelected
                        || desktop.currentDesktop || pointer.containsMouse
                        ? root.theme.accent
                        : Qt.rgba(root.theme.muted.r, root.theme.muted.g, root.theme.muted.b, 0.45)
                }
            }

            Text {
                id: workspaceLabel
                x: 2
                y: canvas.height + 7
                width: Math.max(0, desktop.width - 4)
                height: 20
                text: desktop.label
                textFormat: Text.PlainText
                color: desktop.currentDesktop || desktop.keyboardSelected
                    ? root.theme.foreground : root.theme.muted
                font.pixelSize: 14
                font.bold: desktop.currentDesktop || desktop.keyboardSelected
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                elide: Text.ElideRight
            }

            MouseArea {
                id: pointer
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton
                enabled: !root.controller.busy && !root.dragActive
                onPressed: {
                    root.controller.selectionKind = "workspace";
                    root.controller.selectedWorkspaceId = desktop.workspaceId;
                }
                onClicked: desktop.activate()
            }

            Controls.ToolTip {
                visible: pointer.containsMouse && workspaceLabel.truncated && !root.dragActive
                delay: 600
                contentItem: Text {
                    text: desktop.label
                    textFormat: Text.PlainText
                    color: root.theme.foreground
                }
                background: Rectangle {
                    color: root.theme.background
                    border.color: root.theme.muted
                    radius: 4
                }
            }
        }
    }

    // A viewport-owned DropArea keeps a stationary drag valid while desktops
    // scroll beneath it. Resolve the actual button again on release, not entry.
    DropArea {
        id: stripDrop
        x: desktops.x
        y: desktops.y
        width: desktops.width
        height: desktops.height
        keys: ["omarchycontrol-window"]

        onEntered: function(drag) {
            drag.accepted = !!root.dragWindow(drag.source);
        }
        onPositionChanged: function(drag) {
            drag.accepted = !!root.dragWindow(drag.source);
        }
        onDropped: function(drop) {
            const workspace = root.workspaceAt(drop.x, drop.y);
            if (!workspace || !root.canDrop(drop.source, workspace.workspaceId)) {
                drop.accepted = false;
                return;
            }
            const address = drop.source.address;
            const workspaceId = workspace.workspaceId;
            root._dropCommitted = true;
            root._edgeDirection = 0;
            drop.accept(Qt.MoveAction);
            root.moveRequested(address, workspaceId);
        }
    }
}
