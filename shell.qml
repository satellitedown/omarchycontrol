import QtQuick
import Quickshell
import Quickshell.Io
ShellRoot {
    Theme { id: appTheme }
    OverviewController { id: appController }
    Connections { target: appController; function onOpenedChanged() { if (appController.opened) appTheme.reload() } }
    LazyLoader {
        active: appController.opened
        OverviewWindow { controller: appController; theme: appTheme }
    }
    IpcHandler {
        target: "missioncontrol"
        function ping(): string { return "ok" }
        function show(): void { appController.show() }
        function hide(): void { appController.hide() }
        function toggle(): void { appController.toggle() }
    }
}
