import QtQuick 2.12
import QtQuick.Controls.Basic 2.12

import "../theme"

Rectangle {
    id: root

    property string title: ""
    property bool busy: false

    signal backRequested()

    readonly property color headerBackground: "#2C001E"
    readonly property color headerForeground: "#FFFFFF"
    readonly property color headerPress: "#4A1731"

    readonly property real headerHeight:
        ui.size(78, width, height)

    UiMetrics {
        id: ui
    }

    width: 360
    height: headerHeight

    color: headerBackground

    Item {
        id: backArea

        width: ui.size(88, root.width, root.height)
        height: parent.height

        Rectangle {
            anchors.fill: parent
            radius: ui.size(12, root.width, root.height)

            color: backMouse.pressed
                ? root.headerPress
                : "transparent"
        }

        Text {
            anchors.centerIn: parent

            text: "←"
            color: root.headerForeground

            font.pointSize:
                ui.font(38, root.width, root.height)

            font.weight: Font.DemiBold
        }

        MouseArea {
            id: backMouse

            anchors.fill: parent
            enabled: !root.busy

            onClicked: root.backRequested()
        }
    }

    Text {
        anchors.left: backArea.right
        anchors.right: parent.right

        anchors.leftMargin: 6
        anchors.rightMargin:
            ui.size(24, root.width, root.height)

        anchors.verticalCenter: parent.verticalCenter

        text: root.title
        color: root.headerForeground

        font.pointSize:
            ui.font(25, root.width, root.height)

        font.weight: Font.DemiBold
        elide: Text.ElideRight
    }
}
