import QtQuick
import Quickshell.Wayland

Item {
    id: root

    property var toplevel: null
    property bool live: false
    readonly property bool hasContent: enabled && !!toplevel && capture.hasContent

    property color backgroundColor: "#101315"
    property color foregroundColor: "#cacccc"
    property color mutedColor: "#707880"

    readonly property string appId: toplevel
        ? ((toplevel.wayland ? toplevel.wayland.appId : "")
            || toplevel.lastIpcObject.class || "") : ""
    readonly property string title: toplevel
        ? (toplevel.title || toplevel.lastIpcObject.title || appId || "Untitled window") : ""

    property bool _previewUnavailable: false

    clip: true

    function resetFallback() {
        fallbackTimer.stop();
        _previewUnavailable = false;
        if (enabled && toplevel && !hasContent)
            fallbackTimer.start();
    }

    Component.onCompleted: resetFallback()

    Connections {
        target: root
        function onToplevelChanged() { root.resetFallback(); }
        function onEnabledChanged() { root.resetFallback(); }
        function onHasContentChanged() { root.resetFallback(); }
    }

    Timer {
        id: fallbackTimer
        interval: 1000
        repeat: false
        onTriggered: root._previewUnavailable = true
    }

    Rectangle {
        anchors.fill: parent
        visible: root.enabled && !!root.toplevel && !root.hasContent
        color: root.backgroundColor

        Column {
            anchors.centerIn: parent
            width: Math.max(0, parent.width - 24)
            spacing: 6

            Text {
                width: parent.width
                text: root.title
                textFormat: Text.PlainText
                color: root.foregroundColor
                font.pixelSize: 16
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
            }

            Text {
                width: parent.width
                visible: text.length > 0 && text !== root.title
                text: root.appId
                textFormat: Text.PlainText
                color: root.mutedColor
                font.pixelSize: 12
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
            }

            Text {
                width: parent.width
                visible: root._previewUnavailable
                text: "Preview unavailable"
                textFormat: Text.PlainText
                color: root.mutedColor
                font.pixelSize: 12
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
            }
        }
    }

    ScreencopyView {
        id: capture
        anchors.centerIn: parent
        // Both constraints are required for aspect-correct implicit sizing.
        constraintSize: Qt.size(Math.max(1, root.width), Math.max(1, root.height))
        width: implicitWidth
        height: implicitHeight
        captureSource: root.enabled && root.toplevel ? root.toplevel.wayland : null
        paintCursor: false
        live: root.live
        visible: root.hasContent
        // Quickshell 0.3.1 imports OpenGL DMA-BUF textures without declaring
        // their alpha channel. Composite through an RGBA layer so translucent
        // clients blend with the overview, not punch through to real windows.
        // This target is preview-sized and disappears with the capture.
        layer.enabled: root.hasContent
    }

    Connections {
        target: capture
        // A failed context clears hasContent even when stopped is not emitted.
        // Only a source change creates a new context; the timer never retries.
        function onCaptureSourceChanged() { root.resetFallback(); }
    }
}
