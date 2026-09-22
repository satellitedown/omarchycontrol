import QtQuick
import QtQuick.Controls as Controls
import Quickshell

Item {
    id: root

    required property var controller
    required property var theme
    required property var toplevel
    required property string address
    property bool selected: false
    property real chromeScale: 1

    signal activated()
    signal dragStarted(real x, real y)
    signal dragMoved(real x, real y)
    signal dragFinished()

    readonly property var ipc: toplevel ? (toplevel.lastIpcObject || {}) : ({})
    readonly property string appId: toplevel
        ? ((toplevel.wayland ? toplevel.wayland.appId : "") || ipc.class || "") : ""
    readonly property string title: toplevel
        ? (toplevel.title || ipc.title || appId || "Untitled window") : ""
    readonly property var desktopEntry: appId ? DesktopEntries.heuristicLookup(appId) : null
    readonly property string iconSource: desktopEntry && desktopEntry.icon
        ? Quickshell.iconPath(desktopEntry.icon, true) : ""
    readonly property bool interactive: controller.opened && !controller.busy && !!toplevel
    property bool _dragged: false

    objectName: "window-" + address
    implicitWidth: 480
    implicitHeight: 320

    Accessible.role: Accessible.Button
    Accessible.name: title
    Accessible.description: appId
    Accessible.focusable: true
    Accessible.focused: selected
    Accessible.selected: selected
    Accessible.pressed: tap.pressed

    Rectangle {
        anchors.fill: parent
        radius: 12
        color: root.theme.background
    }

    WindowPreview {
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: 6 * root.chromeScale
        height: Math.max(0, root.height - 38 * root.chromeScale)
        toplevel: root.toplevel
        enabled: root.visible && root.controller.opened && width > 0 && height > 0
        live: enabled
        backgroundColor: root.theme.background
        foregroundColor: root.theme.foreground
        mutedColor: root.theme.muted
    }

    Item {
        id: caption
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.leftMargin: 10 * root.chromeScale
        anchors.rightMargin: 10 * root.chromeScale
        height: Math.min(32 * root.chromeScale, root.height)
        clip: true

        Item {
            id: icon
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: 20 * root.chromeScale
            height: 20 * root.chromeScale

            Image {
                id: appIcon
                anchors.fill: parent
                source: root.iconSource
                sourceSize: Qt.size(20, 20)
                fillMode: Image.PreserveAspectFit
                visible: status === Image.Ready
            }

            Rectangle {
                anchors.centerIn: parent
                width: 18
                height: 15
                radius: 2
                color: "transparent"
                border.width: 1
                border.color: root.theme.foreground
                visible: !appIcon.visible

                Rectangle {
                    x: 1
                    y: 4
                    width: parent.width - 2
                    height: 1
                    color: root.theme.foreground
                }
            }
        }

        Text {
            anchors.left: icon.right
            anchors.right: parent.right
            anchors.leftMargin: 8 * root.chromeScale
            anchors.verticalCenter: parent.verticalCenter
            text: root.title
            textFormat: Text.PlainText
            color: root.theme.foreground
            font.pixelSize: Math.max(1, 14 * root.chromeScale)
            elide: Text.ElideRight
            maximumLineCount: 1
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: 12
        color: "transparent"
        border.width: root.selected || hover.hovered ? 2 : 1
        border.color: root.selected || hover.hovered ? root.theme.accent : root.theme.muted
    }

    HoverHandler {
        id: hover
        enabled: root.interactive
        cursorShape: drag.active ? Qt.ClosedHandCursor : Qt.PointingHandCursor
    }

    TapHandler {
        id: tap
        enabled: root.interactive
        acceptedButtons: Qt.LeftButton
        gesturePolicy: TapHandler.DragThreshold
        dragThreshold: 8
        onPressedChanged: {
            if (pressed && !drag.active)
                root._dragged = false;
        }
        onTapped: {
            if (root.interactive && !root._dragged && !drag.active)
                root.activated();
        }
    }

    DragHandler {
        id: drag
        enabled: root.interactive
        target: null
        acceptedButtons: Qt.LeftButton
        dragThreshold: 8
        onActiveChanged: {
            if (active) {
                root._dragged = true;
                root.dragStarted(centroid.position.x, centroid.position.y);
            } else if (root._dragged) {
                root.dragFinished();
            }
        }
        onCentroidChanged: {
            if (active)
                root.dragMoved(centroid.position.x, centroid.position.y);
        }
    }

    Controls.ToolTip {
        id: tooltip
        visible: hover.hovered && !tap.pressed && !drag.active && root.interactive
        delay: 600
        text: root.title
        width: Math.min(480, contentItem.implicitWidth + leftPadding + rightPadding)
        contentItem: Text {
            text: tooltip.text
            textFormat: Text.PlainText
            color: root.theme.foreground
            font.pixelSize: 14
            wrapMode: Text.Wrap
        }
        background: Rectangle {
            color: root.theme.background
            border.color: root.theme.muted
            radius: 6
        }
    }
}
