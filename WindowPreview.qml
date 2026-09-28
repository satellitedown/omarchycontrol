import QtQuick
import Quickshell.Wayland

Item {
    id: root

    property var toplevel: null
    property bool live: false
    // Miniatures only need a placeholder fill; text at that size is unreadable.
    property bool compact: false
    readonly property bool hasContent: enabled && !!toplevel && capture.hasContent
    readonly property Item captureItem: capture

    property color backgroundColor: "#101315"
    property color foregroundColor: "#cacccc"
    property color mutedColor: "#707880"

    clip: !compact

    Rectangle {
        anchors.fill: parent
        visible: root.enabled && !!root.toplevel && !root.hasContent
        color: root.backgroundColor

        Loader {
            anchors.fill: parent
            active: !root.compact
            sourceComponent: fallbackLabel
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
        // Quickshell 0.3.1 imports DMA-BUF textures without declaring their
        // alpha channel, so at full opacity Qt draws them unblended and
        // translucent clients punch through to the real windows beneath. Just
        // under Qt's 0.999 opaque cutoff the capture takes the blended texture
        // path instead: correct compositing without an offscreen layer.
        opacity: 0.998
    }

    Component {
        id: fallbackLabel

        Item {
            id: label

            readonly property string appId: root.toplevel
                ? ((root.toplevel.wayland ? root.toplevel.wayland.appId : "")
                    || root.toplevel.lastIpcObject.class || "") : ""
            readonly property string title: root.toplevel
                ? (root.toplevel.title || root.toplevel.lastIpcObject.title || appId || "Untitled window") : ""
            property bool unavailable: false

            function reset() {
                unavailableTimer.stop();
                unavailable = false;
                if (root.enabled && root.toplevel && !root.hasContent)
                    unavailableTimer.start();
            }

            Component.onCompleted: reset()

            Connections {
                target: root
                function onToplevelChanged() { label.reset(); }
                function onEnabledChanged() { label.reset(); }
                function onHasContentChanged() { label.reset(); }
            }

            Connections {
                target: capture
                // A failed context clears hasContent even when stopped is not emitted.
                // Only a source change creates a new context; the timer never retries.
                function onCaptureSourceChanged() { label.reset(); }
            }

            Timer {
                id: unavailableTimer
                interval: 1000
                repeat: false
                onTriggered: label.unavailable = true
            }

            Column {
                anchors.centerIn: parent
                width: Math.max(0, parent.width - 24)
                spacing: 6

                Text {
                    width: parent.width
                    text: label.title
                    textFormat: Text.PlainText
                    color: root.foregroundColor
                    font.pixelSize: 16
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                }

                Text {
                    width: parent.width
                    visible: text.length > 0 && text !== label.title
                    text: label.appId
                    textFormat: Text.PlainText
                    color: root.mutedColor
                    font.pixelSize: 12
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                }

                Text {
                    width: parent.width
                    visible: label.unavailable
                    text: "Preview unavailable"
                    textFormat: Text.PlainText
                    color: root.mutedColor
                    font.pixelSize: 12
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                }
            }
        }
    }
}
