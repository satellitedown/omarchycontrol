import QtQuick
import QtQml.Models
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import "OverviewModel.js" as Model

Item {
    id: root

    property bool opened: false
    property bool closing: false
    property string targetMonitorName: ""
    property var targetMonitor: null
    property var targetScreen: null
    readonly property alias workspaceModel: workspaces
    readonly property alias windowModel: windows
    property string selectedAddress: ""
    property int selectedWorkspaceId: 0
    property string selectionKind: "workspace"
    property string errorMessage: ""
    readonly property bool busy: closing || _action !== null
    property int revision: 0

    signal cancelDrag()
    signal closeRequested()

    property int _activeWorkspaceId: 0
    property string _openingAddress: ""
    property int _openingWorkspaceId: 0
    property bool _openingWindowMoved: false
    property bool _firstReconcile: true
    property bool _openingRefreshPending: false
    property bool _selectionPending: false
    property bool _reconciling: false
    property bool _reconcileQueued: false
    property string _snapshotSignature: ""
    property var _snapshotHandles: ({})
    property var _action: null
    property var _pendingRestore: null

    onSelectedAddressChanged: if (!_reconciling) _selectionPending = false
    onSelectedWorkspaceIdChanged: if (!_reconciling) _selectionPending = false
    onSelectionKindChanged: if (!_reconciling) _selectionPending = false

    ListModel { id: workspaces; dynamicRoles: true }
    ListModel { id: windows; dynamicRoles: true }

    function addressOf(toplevel) {
        if (!toplevel)
            return "";
        const ipc = toplevel.lastIpcObject;
        return Model.normalizeAddress(ipc && ipc.address ? ipc.address : toplevel.address);
    }

    function findWindow(address) {
        const canonical = Model.normalizeAddress(address);
        if (!canonical)
            return null;
        const values = Hyprland.toplevels.values;
        for (let i = 0; i < values.length; ++i) {
            if (addressOf(values[i]) === canonical)
                return values[i];
        }
        return null;
    }

    function _monitorByName(name) {
        const values = Hyprland.monitors.values;
        for (let i = 0; i < values.length; ++i) {
            if (values[i].name === name)
                return values[i];
        }
        return null;
    }

    function _screenByName(name) {
        const values = Quickshell.screens;
        for (let i = 0; i < values.length; ++i) {
            if (values[i].name === name)
                return values[i];
        }
        return null;
    }

    function _workspaceById(id, monitor) {
        if (!monitor)
            return null;
        const values = Hyprland.workspaces.values;
        for (let i = 0; i < values.length; ++i) {
            const workspace = values[i];
            if (workspace.id === id && Model.isNormalWorkspace(workspace)
                    && workspace.monitor && workspace.monitor.id === monitor.id)
                return workspace;
        }
        const active = monitor.activeWorkspace;
        return active && active.id === id && Model.isNormalWorkspace(active)
                && active.monitor && active.monitor.id === monitor.id ? active : null;
    }

    function _indexOf(model, role, value) {
        for (let i = 0; i < model.count; ++i) {
            if (model.get(i)[role] === value)
                return i;
        }
        return -1;
    }

    function show() {
        if (opened || busy)
            return;
        const monitor = Hyprland.focusedMonitor;
        if (!monitor || !_openOnMonitor(monitor.name, "", null)) {
            errorMessage = "No active Hyprland monitor.";
            console.error(errorMessage);
        }
    }

    function _openOnMonitor(name, message, restoreContext) {
        const monitor = _monitorByName(name);
        const screen = _screenByName(name);
        if (!monitor || !screen)
            return false;
        _pendingRestore = null;
        _reconciling = true;
        targetMonitorName = name;
        targetMonitor = monitor;
        targetScreen = screen;
        _openingAddress = restoreContext ? restoreContext.address : addressOf(Hyprland.activeToplevel);
        _openingWorkspaceId = restoreContext ? restoreContext.workspaceId
                : (monitor.activeWorkspace ? monitor.activeWorkspace.id : 0);
        _openingWindowMoved = false;
        _activeWorkspaceId = 0;
        _firstReconcile = true;
        _openingRefreshPending = true;
        selectedAddress = "";
        selectedWorkspaceId = 0;
        selectionKind = "workspace";
        _selectionPending = !!_openingAddress;
        errorMessage = message;
        closing = false;
        opened = true;
        _reconciling = false;
        refresh();
        return true;
    }

    function _restoreContext() {
        return { address: _openingAddress, workspaceId: _openingWorkspaceId,
            monitorName: targetMonitorName };
    }

    function hide() {
        if (!opened || closing)
            return;
        const movingOpeningWindow = _action && _action.kind === "move"
                && _action.address === _openingAddress
                && _action.workspaceId !== _openingWorkspaceId;
        _pendingRestore = _openingWindowMoved || movingOpeningWindow ? null : _restoreContext();
        _requestClose();
    }

    function toggle() {
        if (opened)
            hide();
        else
            show();
    }

    function _requestClose() {
        if (!opened || closing)
            return;
        cancelDrag();
        closing = true;
        closeGuard.restart();
        closeRequested();
    }

    // Called after the exit motion, or immediately when its output disappears.
    function finishClose() {
        if (!opened)
            return;
        closeGuard.stop();
        cancelDrag();
        refreshTimer.stop();
        opened = false;
        closing = false;
        _reconcileQueued = false;
        _selectionPending = false;
        _openingRefreshPending = false;
        windows.clear();
        workspaces.clear();
        _snapshotSignature = "";
        _snapshotHandles = ({});
        targetMonitor = null;
        targetScreen = null;
        // Only now is it safe to hand focus back to a real client.
        Qt.callLater(_dispatchAction);
        Qt.callLater(_restoreFocus);
    }

    function _checkTarget() {
        if (!opened)
            return false;
        const monitor = _monitorByName(targetMonitorName);
        const screen = _screenByName(targetMonitorName);
        if (!monitor || !screen) {
            _pendingRestore = null;
            finishClose();
            return false;
        }
        targetMonitor = monitor;
        targetScreen = screen;
        return true;
    }

    function refresh() {
        if (!_checkTarget())
            return;
        Hyprland.refreshMonitors();
        Hyprland.refreshWorkspaces();
        Hyprland.refreshToplevels();
        // Refresh requests are asynchronous; object signals reconcile each reply.
        reconcile();
    }

    function _queueReconcile() {
        if (!opened || _reconcileQueued)
            return;
        _reconcileQueued = true;
        Qt.callLater(_flushReconcile);
    }

    function _flushReconcile() {
        _reconcileQueued = false;
        if (opened)
            reconcile();
    }

    function _workspaceRows() {
        const rows = [];
        const seen = ({});
        const values = Hyprland.workspaces.values;
        const active = targetMonitor.activeWorkspace;
        for (let i = 0; i <= values.length; ++i) {
            const workspace = i < values.length ? values[i] : active;
            if (!workspace || !Model.isNormalWorkspace(workspace)
                    || !workspace.monitor || workspace.monitor.id !== targetMonitor.id
                    || seen[workspace.id])
                continue;
            seen[workspace.id] = true;
            const named = Model.workspaceSelector(workspace).indexOf("name:") === 0;
            rows.push({ workspaceId: workspace.id, name: workspace.name,
                label: named ? workspace.name : "Desktop " + workspace.id });
        }
        rows.sort(function(a, b) {
            const aNamed = Model.workspaceSelector({ id: a.workspaceId, name: a.name }).indexOf("name:") === 0;
            const bNamed = Model.workspaceSelector({ id: b.workspaceId, name: b.name }).indexOf("name:") === 0;
            if (aNamed !== bNamed)
                return aNamed ? 1 : -1;
            if (!aNamed)
                return a.workspaceId - b.workspaceId;
            return a.name < b.name ? -1 : a.name > b.name ? 1 : a.workspaceId - b.workspaceId;
        });
        return rows;
    }

    function _rowsInvalidated(model, rows, key) {
        for (let i = 0; i < model.count; ++i) {
            const old = model.get(i);
            let found = false;
            for (let j = 0; j < rows.length; ++j) {
                if (old[key] === rows[j][key]) {
                    found = key !== "address" || old.toplevel === rows[j].toplevel;
                    break;
                }
            }
            if (!found)
                return true;
        }
        return false;
    }

    function _syncRows(model, rows, key) {
        const wanted = ({});
        for (let i = 0; i < rows.length; ++i)
            wanted[rows[i][key]] = true;
        for (let i = model.count - 1; i >= 0; --i) {
            if (!wanted[model.get(i)[key]])
                model.remove(i);
        }
        for (let i = 0; i < rows.length; ++i) {
            const row = rows[i];
            const oldIndex = _indexOf(model, key, row[key]);
            if (oldIndex < 0) {
                model.insert(i, row);
                continue;
            }
            if (oldIndex !== i)
                model.move(oldIndex, i, 1);
            const old = model.get(i);
            for (const role in row) {
                if (old[role] !== row[role])
                    model.setProperty(i, role, row[role]);
            }
        }
    }

    function reconcile() {
        if (_reconciling || !_checkTarget())
            return;
        _reconciling = true;
        const active = targetMonitor.activeWorkspace;
        const workspaceId = active ? active.id : 0;
        const workspaceChanged = !_firstReconcile && workspaceId !== _activeWorkspaceId;
        const rebuild = _firstReconcile || workspaceChanged;
        const oldWindowIndex = _indexOf(windows, "address", selectedAddress);
        const oldWorkspaceIndex = _indexOf(workspaces, "workspaceId", selectedWorkspaceId);
        const workspaceRows = _workspaceRows();
        const eligible = ({});
        const additions = [];
        const values = Hyprland.toplevels.values;
        for (let i = 0; i < values.length; ++i) {
            const toplevel = values[i];
            const address = addressOf(toplevel);
            if (address && !eligible[address]
                    && Model.windowEligible(toplevel.lastIpcObject, targetMonitor.id, workspaceId)) {
                const row = { address: address, toplevel: toplevel };
                eligible[address] = row;
                additions.push(row);
            }
        }
        additions.sort(function(a, b) {
            return Model.spatialCompare(a.toplevel.lastIpcObject, b.toplevel.lastIpcObject);
        });
        const windowRows = [];
        const retained = ({});
        if (!rebuild) {
            for (let i = 0; i < windows.count; ++i) {
                const address = windows.get(i).address;
                if (eligible[address]) {
                    windowRows.push(eligible[address]);
                    retained[address] = true;
                }
            }
        }
        for (let i = 0; i < additions.length; ++i) {
            if (!retained[additions[i].address])
                windowRows.push(additions[i]);
        }
        if (workspaceChanged || _rowsInvalidated(windows, windowRows, "address")
                || _rowsInvalidated(workspaces, workspaceRows, "workspaceId"))
            cancelDrag();
        _syncRows(workspaces, workspaceRows, "workspaceId");
        _syncRows(windows, windowRows, "address");
        _activeWorkspaceId = workspaceId;

        if (workspaceChanged) {
            _selectionPending = false;
            const focused = addressOf(Hyprland.activeToplevel);
            selectedAddress = eligible[focused] ? focused : (windows.count ? windows.get(0).address : "");
            selectedWorkspaceId = workspaceId;
            selectionKind = windows.count ? "window" : "workspace";
        } else if (_selectionPending && eligible[_openingAddress]) {
            selectedAddress = _openingAddress;
            selectionKind = "window";
            _selectionPending = false;
        } else if (_indexOf(windows, "address", selectedAddress) < 0) {
            selectedAddress = windows.count
                    ? windows.get(Math.min(Math.max(oldWindowIndex, 0), windows.count - 1)).address : "";
            if (_firstReconcile)
                selectionKind = windows.count ? "window" : "workspace";
        }
        if (!windows.count)
            selectionKind = "workspace";
        if (_indexOf(workspaces, "workspaceId", selectedWorkspaceId) < 0) {
            const currentIndex = _indexOf(workspaces, "workspaceId", workspaceId);
            const nearest = Math.min(Math.max(oldWorkspaceIndex, 0), workspaces.count - 1);
            selectedWorkspaceId = currentIndex >= 0 ? workspaceId
                    : (nearest >= 0 ? workspaces.get(nearest).workspaceId : 0);
        }
        _firstReconcile = false;
        _updateSnapshotRevision(workspaceRows);
        _reconciling = false;
    }

    function _validGeometry(ipc) {
        return ipc && ipc.at && ipc.size && ipc.at.length >= 2 && ipc.size.length >= 2
                && typeof ipc.at[0] === "number" && isFinite(ipc.at[0])
                && typeof ipc.at[1] === "number" && isFinite(ipc.at[1])
                && typeof ipc.size[0] === "number" && isFinite(ipc.size[0]) && ipc.size[0] > 0
                && typeof ipc.size[1] === "number" && isFinite(ipc.size[1]) && ipc.size[1] > 0;
    }

    function windowsForWorkspace(id) {
        const result = [];
        if (!opened || !targetMonitor || !_workspaceById(id, targetMonitor))
            return result;
        const seen = ({});
        const values = Hyprland.toplevels.values;
        for (let i = 0; i < values.length; ++i) {
            const toplevel = values[i];
            const ipc = toplevel.lastIpcObject;
            const address = addressOf(toplevel);
            if (!address || seen[address] || !Model.windowEligible(ipc, targetMonitor.id, id)
                    || !_validGeometry(ipc))
                continue;
            seen[address] = true;
            result.push({ address: address, toplevel: toplevel,
                at: [ipc.at[0], ipc.at[1]], size: [ipc.size[0], ipc.size[1]],
                focusHistoryID: typeof ipc.focusHistoryID === "number" && ipc.focusHistoryID >= 0
                    ? ipc.focusHistoryID : Number.MAX_SAFE_INTEGER });
        }
        result.sort(function(a, b) {
            return b.focusHistoryID - a.focusHistoryID
                    || (a.address < b.address ? -1 : a.address > b.address ? 1 : 0);
        });
        return result;
    }

    function _updateSnapshotRevision(workspaceRows) {
        const metadata = [targetMonitor.x, targetMonitor.y, targetScreen.width, targetScreen.height, workspaceRows];
        const handles = ({});
        let handlesChanged = false;
        for (let i = 0; i < workspaceRows.length; ++i) {
            const clients = windowsForWorkspace(workspaceRows[i].workspaceId);
            const workspaceMetadata = [];
            for (let j = 0; j < clients.length; ++j) {
                const client = clients[j];
                workspaceMetadata.push([client.address, client.at, client.size, client.focusHistoryID]);
                handles[client.address] = client.toplevel.wayland;
                if (_snapshotHandles[client.address] !== handles[client.address])
                    handlesChanged = true;
            }
            metadata.push(workspaceMetadata);
        }
        const signature = JSON.stringify(metadata);
        if (handlesChanged || signature !== _snapshotSignature) {
            _snapshotSignature = signature;
            _snapshotHandles = handles;
            revision += 1;
        }
    }

    function _availableWindow(address, monitor) {
        const toplevel = findWindow(address);
        return toplevel && monitor && monitor.activeWorkspace
                && Model.windowEligible(toplevel.lastIpcObject, monitor.id, monitor.activeWorkspace.id)
                ? toplevel : null;
    }

    function _unavailable() {
        errorMessage = "Window or desktop is no longer available.";
        cancelDrag();
        refresh();
    }

    function activateWindow(address) {
        if (!opened || busy)
            return;
        const toplevel = _availableWindow(address, targetMonitor);
        if (!toplevel) {
            _unavailable();
            return;
        }
        _startAction("window", addressOf(toplevel), 0);
    }

    function activateWorkspace(id) {
        if (!opened || busy)
            return;
        if (!_workspaceById(id, targetMonitor) || _indexOf(workspaces, "workspaceId", id) < 0) {
            _unavailable();
            return;
        }
        _startAction("workspace", "", id);
    }

    function moveWindow(address, workspaceId) {
        if (!opened || busy)
            return;
        const toplevel = _availableWindow(address, targetMonitor);
        const workspace = _workspaceById(workspaceId, targetMonitor);
        if (!toplevel || !workspace || _indexOf(workspaces, "workspaceId", workspaceId) < 0) {
            _unavailable();
            return;
        }
        errorMessage = "";
        if (toplevel.lastIpcObject.workspace.id === workspaceId)
            return;
        _startAction("move", addressOf(toplevel), workspaceId);
    }

    function _startAction(kind, address, workspaceId) {
        errorMessage = "";
        _action = { kind: kind, address: address, workspaceId: workspaceId,
            monitorName: targetMonitorName, restoreContext: _restoreContext(), launched: false };
        if (kind === "window" || kind === "workspace")
            _requestClose();
        else
            Qt.callLater(_dispatchAction);
    }

    function _canRestore(context) {
        if (!context || !context.address)
            return false;
        const monitor = _monitorByName(context.monitorName);
        const toplevel = findWindow(context.address);
        const ipc = toplevel ? toplevel.lastIpcObject : null;
        return !!(monitor && _screenByName(context.monitorName) && monitor.activeWorkspace
                && monitor.activeWorkspace.id === context.workspaceId
                && ipc && ipc.mapped && !ipc.hidden && ipc.monitor === monitor.id
                && ipc.workspace && ipc.workspace.id === context.workspaceId
                && Model.isNormalWorkspace(ipc.workspace));
    }

    function _restoreFocus() {
        if (opened || busy || !_pendingRestore)
            return;
        const context = _pendingRestore;
        _pendingRestore = null;
        if (!_canRestore(context))
            return;
        _action = { kind: "restore", address: context.address, workspaceId: context.workspaceId,
            monitorName: context.monitorName, restoreContext: context, launched: false };
        _dispatchAction();
    }

    function _dispatchAction() {
        const action = _action;
        if (!action || action.launched || (opened && action.kind !== "move"))
            return;
        const monitor = _monitorByName(action.monitorName);
        const toplevel = action.kind === "workspace" ? null : _availableWindow(action.address, monitor);
        const workspace = action.kind === "workspace" || action.kind === "move"
                ? _workspaceById(action.workspaceId, monitor) : null;
        if (action.kind === "restore" && !_canRestore(action.restoreContext)) {
            _action = null;
            return;
        }
        if (!monitor || !_screenByName(action.monitorName)
                || (action.kind !== "workspace" && !toplevel)
                || ((action.kind === "workspace" || action.kind === "move") && !workspace)) {
            _finishAction(false, "The source window or target desktop disappeared before dispatch.", true);
            return;
        }
        const windowSelector = Model.luaQuote("address:" + action.address);
        let expression;
        if (action.kind === "workspace") {
            expression = "hl.dsp.focus({ workspace = " + Model.luaQuote(Model.workspaceSelector(workspace)) + " })";
        } else if (action.kind === "move") {
            if (toplevel.lastIpcObject.workspace.id === action.workspaceId) {
                _action = null;
                Qt.callLater(_restoreFocus);
                return;
            }
            expression = "hl.dsp.window.move({ workspace = " + Model.luaQuote(Model.workspaceSelector(workspace))
                    + ", follow = false, window = " + windowSelector + " })";
        } else {
            expression = "hl.dsp.focus({ window = " + windowSelector + " })";
        }
        action.launched = true;
        if (action.kind === "window") {
            // Focusing alone can leave an already-active floating client occluded.
            // Batch both dispatches after the overview releases its input grab.
            const raise = "hl.dsp.window.alter_zorder({ mode = \"top\", window = " + windowSelector + " })";
            actionProcess.command = ["hyprctl", "--batch", "dispatch " + expression + "; dispatch " + raise];
        } else {
            actionProcess.command = ["hyprctl", "dispatch", expression];
        }
        actionProcess.running = true;
    }

    function _finishAction(success, diagnostic, unavailable) {
        const action = _action;
        if (!action)
            return;
        _action = null;
        if (success) {
            if (action.kind === "move" && action.address === _openingAddress
                    && action.workspaceId !== _openingWorkspaceId)
                _openingWindowMoved = true;
            if (opened)
                refresh();
        } else {
            console.error("Mission control " + action.kind + ": " + diagnostic);
            const message = unavailable ? "Window or desktop is no longer available."
                    : action.kind === "move" ? "Could not move window."
                    : action.kind === "workspace" ? "Could not switch desktop." : "Could not activate window.";
            errorMessage = message;
            if (action.kind === "window" || action.kind === "workspace")
                _openOnMonitor(action.monitorName, message, action.restoreContext);
            else if (opened)
                refresh();
        }
        Qt.callLater(_restoreFocus);
    }

    function _checkProcessStopped() {
        // FailedToStart emits runningChanged but not exited in Quickshell 0.3.1.
        if (_action && _action.launched && !actionProcess.running)
            _finishAction(false, "hyprctl failed to start; see the process diagnostic above.", false);
    }

    Process {
        id: actionProcess
        stdout: StdioCollector { id: actionOutput; waitForEnd: true }
        stderr: StdioCollector { id: actionError; waitForEnd: true }
        onExited: function(exitCode, exitStatus) {
            const response = actionOutput.text.trim();
            const replies = response.split(/\s+/);
            const expected = root._action && root._action.kind === "window" ? 2 : 1;
            const success = exitCode === 0 && exitStatus === 0
                && replies.length === expected && replies.every(reply => reply === "ok");
            root._finishAction(success, "exit=" + exitCode + ", status=" + exitStatus
                + ", response=" + response + ", stderr=" + actionError.text.trim(), false);
        }
        onRunningChanged: if (!running) Qt.callLater(root._checkProcessStopped)
    }

    Timer {
        id: refreshTimer
        interval: 50
        repeat: false
        onTriggered: root.refresh()
    }

    // The overlay owns the exit motion and reports back when it finishes. This
    // bound keeps a missing or wedged overlay from leaving the controller open.
    Timer {
        id: closeGuard
        interval: 700
        repeat: false
        onTriggered: root.finishClose()
    }

    Connections {
        target: Hyprland
        enabled: root.opened
        function onRawEvent(event) {
            const name = event.name;
            if (name === "monitorremoved" && event.data === root.targetMonitorName) {
                root._pendingRestore = null;
                root.finishClose();
                return;
            }
            if (name === "monitorremovedv2") {
                const parts = event.parse(3);
                if (parts[1] === root.targetMonitorName) {
                    root._pendingRestore = null;
                    root.finishClose();
                    return;
                }
            }
            switch (name) {
            case "openwindow": case "closewindow": case "movewindowv2": case "workspacev2":
            case "createworkspacev2": case "destroyworkspacev2": case "moveworkspacev2":
            case "renameworkspace": case "fullscreen": case "changefloatingmode": case "pin":
            case "minimized": case "togglegroup": case "moveintogroup": case "moveoutofgroup":
            case "monitoraddedv2": case "monitorremovedv2": case "configreloaded":
                if (!refreshTimer.running)
                    refreshTimer.start();
                break;
            }
        }
    }

    Connections {
        target: Quickshell
        enabled: root.opened
        function onScreensChanged() {
            if (root._checkTarget())
                root._queueReconcile();
        }
    }

    Connections {
        target: Hyprland.monitors
        enabled: root.opened
        function onValuesChanged() {
            if (root._checkTarget())
                root._queueReconcile();
        }
    }

    Connections {
        target: Hyprland.workspaces
        enabled: root.opened
        function onValuesChanged() { root.reconcile(); }
    }

    Connections {
        target: Hyprland.toplevels
        enabled: root.opened
        function onValuesChanged() { root.reconcile(); }
    }

    Connections {
        target: root.opened ? root.targetMonitor : null
        function onActiveWorkspaceChanged() { root.reconcile(); }
        function onLastIpcObjectChanged() { root._queueReconcile(); }
        function onXChanged() { root._queueReconcile(); }
        function onYChanged() { root._queueReconcile(); }
        function onWidthChanged() { root._queueReconcile(); }
        function onHeightChanged() { root._queueReconcile(); }
        function onScaleChanged() { root._queueReconcile(); }
    }

    Instantiator {
        model: root.opened ? Hyprland.toplevels : null
        delegate: Connections {
            required property var modelData
            target: modelData
            function onLastIpcObjectChanged() { root._queueReconcile(); }
            function onWorkspaceChanged() { root._queueReconcile(); }
            function onMonitorChanged() { root._queueReconcile(); }
            function onAddressChanged() {
                // updateFromObject emits this even for an unchanged address.
                // Coalesce to the end of the async reply before fixing opening order.
                if (root._openingRefreshPending) {
                    root._openingRefreshPending = false;
                    root._firstReconcile = true;
                }
                root._queueReconcile();
            }
            function onWaylandHandleChanged() { root._queueReconcile(); }
        }
    }

    Instantiator {
        model: root.opened ? Hyprland.workspaces : null
        delegate: Connections {
            required property var modelData
            target: modelData
            function onIdChanged() { root._queueReconcile(); }
            function onNameChanged() { root._queueReconcile(); }
            function onMonitorChanged() { root._queueReconcile(); }
            function onLastIpcObjectChanged() { root._queueReconcile(); }
        }
    }
}
