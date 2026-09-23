import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
    id: root

    property color background: "#101315"
    property color foreground: "#cacccc"
    property color accent: "#cacccc"
    property color muted: "#707880"

    // Wallpaper-facing chrome stays legible independently of the app palette.
    readonly property color overviewText: "#f5f5f7"
    readonly property color overviewMuted: "#c0c4cc"
    readonly property color overviewAccent: "#0a84ff"
    property string _wallpaperPath: ""
    readonly property url wallpaperSource: _wallpaperPath
        ? "file://" + _wallpaperPath.split("/").map(encodeURIComponent).join("/") : ""

    function reload(): void {
        colorsFile.reload()
        if (!wallpaperProcess.running)
            wallpaperProcess.running = true
    }

    function loadColors(raw): void {
        var lines = String(raw || "").split("\n")
        var loadedBackground = false
        var loadedForeground = false
        var foundAccent = false
        var foundMuted = false
        var color0Value = ""
        var color4Value = ""
        var color7Value = ""
        var color8Value = ""

        for (var i = 0; i < lines.length; i++) {
            // Keep Omarchy's six-digit palette format, but reject malformed
            // values instead of accepting a valid-looking prefix.
            var match = lines[i].match(/^\s*([A-Za-z0-9_-]+)\s*=\s*(["']?)(#[0-9A-Fa-f]{6})\2\s*(?:#.*)?$/)
            if (!match) continue
            if (match[1] === "background") { background = match[3]; loadedBackground = true }
            else if (match[1] === "foreground") { foreground = match[3]; loadedForeground = true }
            else if (match[1] === "accent") { accent = match[3]; foundAccent = true }
            else if (match[1] === "muted") { muted = match[3]; foundMuted = true }
            else if (match[1] === "color0") color0Value = match[3]
            else if (match[1] === "color4") color4Value = match[3]
            else if (match[1] === "color7") color7Value = match[3]
            else if (match[1] === "color8") color8Value = match[3]
        }

        // Explicit roles win regardless of file order. Missing or invalid
        // roles retain their previous usable value, including at startup.
        if (!loadedBackground && color0Value.length > 0) background = color0Value
        if (!loadedForeground && color7Value.length > 0) foreground = color7Value
        if (!foundAccent && color4Value.length > 0) accent = color4Value
        if (!foundMuted && color8Value.length > 0) muted = color8Value
    }

    Component.onCompleted: reload()

    // Resolve the symlink on opening, as Omarchy's background plugin does.
    // The real path is also the image cache key, so theme changes cannot reuse
    // a stale image under the unchanged "current/background" symlink.
    property Process wallpaperProcess: Process {
        command: ["readlink", "-e", Quickshell.env("HOME") + "/.local/state/omarchy/current/background"]
        stdout: StdioCollector { id: wallpaperOutput; waitForEnd: true }
        onExited: (exitCode, exitStatus) => {
            root._wallpaperPath = exitCode === 0 && exitStatus === 0
                ? wallpaperOutput.text.trim() : ""
        }
    }

    property FileView colorsFile: FileView {
        path: Quickshell.env("HOME") + "/.local/state/omarchy/current/theme/colors.toml"
        watchChanges: true
        printErrors: false
        onLoaded: root.loadColors(text())
        // The cached text is stale during fileChanged; parse after reload.
        onFileChanged: root.reload()
    }
}
