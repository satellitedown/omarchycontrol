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
        x: preview.x - 3 * root.chromeScale
        y: preview.y + 3 * root.chromeScale
        width: preview.width + 6 * root.chromeScale
        height: preview.height + 3 * root.chromeScale
        radius: 7 * root.chromeScale
        color: "#18000000"
        visible: preview.width > 0 && preview.height > 0
    }

    Rectangle {
        x: preview.x - root.chromeScale
        y: preview.y + 2 * root.chromeScale
        width: preview.width + 2 * root.chromeScale
        height: preview.height + root.chromeScale
        radius: 4 * root.chromeScale
        color: "#30000000"
        visible: preview.width > 0 && preview.height > 0
    }

    WindowPreview {
        id: preview
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

    Rectangle {
        anchors.fill: preview
        color: "transparent"
        border.width: Math.min(1, root.chromeScale)
        border.color: "#38ffffff"
        visible: preview.width > 0 && preview.height > 0
    }

    Rectangle {
        anchors.fill: preview
        anchors.margins: -3 * root.chromeScale
        radius: 4 * root.chromeScale
        color: "transparent"
        border.width: 2 * root.chromeScale
        border.color: root.theme.overviewAccent
        opacity: root.selected ? 1 : (hover.hovered ? 0.75 : 0)
        visible: preview.width > 0 && preview.height > 0

        Behavior on opacity {
            NumberAnimation { duration: 100; easing.type: Easing.OutCubic }
        }
    }

    Item {
        id: caption
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.leftMargin: 6 * root.chromeScale
        anchors.rightMargin: 6 * root.chromeScale
        height: Math.max(0, Math.min(32 * root.chromeScale, root.height))
        clip: true

        Rectangle {
            id: badge
            anchors.centerIn: parent
            width: Math.max(0, Math.min(caption.width,
                titleLabel.implicitWidth + 42 * root.chromeScale))
            height: Math.min(caption.height, 26 * root.chromeScale)
            radius: 8 * root.chromeScale
            color: "#a6222429"
            clip: true

            Item {
                id: icon
                anchors.left: parent.left
                anchors.leftMargin: 7 * root.chromeScale
                anchors.verticalCenter: parent.verticalCenter
                width: 18 * root.chromeScale
                height: 18 * root.chromeScale

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
                    width: 16 * root.chromeScale
                    height: 13 * root.chromeScale
                    radius: 2 * root.chromeScale
                    color: "transparent"
                    border.width: Math.min(1, root.chromeScale)
                    border.color: root.theme.overviewText
                    visible: !appIcon.visible

                    Rectangle {
                        x: root.chromeScale
                        y: 4 * root.chromeScale
                        width: Math.max(0, parent.width - 2 * root.chromeScale)
                        height: root.chromeScale
                        color: root.theme.overviewText
                    }
                }
            }

            Text {
                id: titleLabel
                x: icon.x + icon.width + 6 * root.chromeScale
                width: Math.max(0, badge.width - x - 11 * root.chromeScale)
                anchors.verticalCenter: parent.verticalCenter
                text: root.title
                textFormat: Text.PlainText
                color: root.theme.overviewText
                font.pixelSize: Math.max(1, 13 * root.chromeScale)
                elide: Text.ElideRight
                maximumLineCount: 1
            }
        }
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
            color: root.theme.overviewText
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
