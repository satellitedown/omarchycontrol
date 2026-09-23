import QtQuick
import Quickshell
import Quickshell.Io
ShellRoot {
    Theme { id: appTheme }
    OverviewController { id: appController }
    Connections { target: appController; function onOpenedChanged() { if (appController.opened) appTheme.reload() } }
    // Keep only the static scene/wallpaper warm. Closing clears both models,
    // destroying window captures, and unmaps the panel via controller.opened.
    OverviewWindow { controller: appController; theme: appTheme }
    IpcHandler {
        target: "missioncontrol"
        function ping(): string { return "ok" }
        function show(): void { appController.show() }
        function hide(): void { appController.hide() }
        function toggle(): void { appController.toggle() }
    }
}
