import QtQuick
import Quickshell
import Quickshell.Io
ShellRoot {
    Theme { id: appTheme }
    OverviewController { id: appController }
    Connections { target: appController; function onOpenedChanged() { if (appController.opened) appTheme.reload() } }
    // Keep the overlay mapped so the wallpaper stays decoded. Closing clears
    // window captures; the panel itself stays input-transparent while closed.
    OverviewWindow { controller: appController; theme: appTheme }
    IpcHandler {
        target: "missioncontrol"
        function ping(): string { return "ok" }
        function show(): void { appController.show() }
        function hide(): void { appController.hide() }
        function toggle(): void { appController.toggle() }
    }
}
