import QtQuick 2.12
import QtQuick.Controls.Basic 2.12

import "../theme"

Item {
    id: root

    property int noteId: -1
    property string title: ""
    property string body: ""
    property string updatedAt: ""

    property bool opened: false
    property bool deleteEnabled: true

    property real viewportWidth: 360
    property real viewportHeight: 640

    readonly property color deleteColor: "#C62828"
    readonly property color deletePressed: "#9E1F1F"
    readonly property color cardColor: "#FFFFFF"
    readonly property color cardBorder: "#D8D3D7"
    readonly property color textPrimary: "#2D252B"
    readonly property color textSecondary: "#6F676D"

    readonly property real deleteRevealWidth:
        ui.size(108, viewportWidth, viewportHeight)

    readonly property real deleteThreshold:
        ui.size(54, viewportWidth, viewportHeight)

    signal deleteRequested(int noteId, string title)
    signal openSwipeRequested()
    signal closeSwipeRequested()
    signal editRequested(int noteId)

    UiMetrics {
        id: ui
    }

    height: ui.size(154, viewportWidth, viewportHeight)

    onOpenedChanged: {
        card.x = root.opened
            ? -root.deleteRevealWidth
            : 0
    }

    onVisibleChanged: {
        if (!visible)
            card.x = 0
    }

    Component.onCompleted: {
        card.x = root.opened
            ? -root.deleteRevealWidth
            : 0
    }

    Rectangle {
        anchors.fill: parent
        radius: ui.size(16, root.viewportWidth, root.viewportHeight)
        color: root.deleteColor

        Button {
            id: deleteButton

            anchors.right: parent.right
            anchors.top: parent.top
            anchors.bottom: parent.bottom

            width: root.deleteRevealWidth

            enabled: root.deleteEnabled

            background: Rectangle {
                radius: ui.size(16, root.viewportWidth, root.viewportHeight)

                color: deleteButton.pressed
                    ? root.deletePressed
                    : root.deleteColor
            }

            contentItem: Column {
                anchors.centerIn: parent

                spacing: ui.size(
                    4,
                    root.viewportWidth,
                    root.viewportHeight
                )

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter

                    text: "×"
                    color: "#FFFFFF"

                    font.pointSize:
                        ui.font(
                            28,
                            root.viewportWidth,
                            root.viewportHeight
                        )

                    font.weight: Font.DemiBold
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter

                    text: "Delete"
                    color: "#FFFFFF"

                    font.pointSize:
                        ui.font(
                            14,
                            root.viewportWidth,
                            root.viewportHeight
                        )

                    font.weight: Font.DemiBold
                }
            }

            onClicked: {
                root.deleteRequested(root.noteId, root.title)
            }
        }
    }

    Rectangle {
        id: card

        width: parent.width
        height: parent.height

        x: root.opened
            ? -root.deleteRevealWidth
            : 0

        radius: ui.size(
            16,
            root.viewportWidth,
            root.viewportHeight
        )

        color: cardMouse.pressed
            ? "#EEE8EC"
            : root.cardColor

        border.color: root.cardBorder
        border.width: 1

        Behavior on x {
            NumberAnimation {
                duration: 150
                easing.type: Easing.OutCubic
            }
        }

        Column {
            anchors.fill: parent

            anchors.margins:
                ui.size(
                    20,
                    root.viewportWidth,
                    root.viewportHeight
                )

            spacing:
                ui.size(
                    8,
                    root.viewportWidth,
                    root.viewportHeight
                )

            Text {
                width: parent.width

                text: root.title
                color: root.textPrimary

                font.pointSize:
                    ui.font(
                        21,
                        root.viewportWidth,
                        root.viewportHeight
                    )

                font.weight: Font.DemiBold
                elide: Text.ElideRight
            }

            Text {
                width: parent.width

                text: root.body.replace(/\s+/g, " ")
                color: root.textSecondary

                font.pointSize:
                    ui.font(
                        18,
                        root.viewportWidth,
                        root.viewportHeight
                    )

                maximumLineCount: 2
                elide: Text.ElideRight
                wrapMode: Text.WordWrap
            }

            Text {
                width: parent.width

                text: root.updatedAt
                color: "#918990"

                font.pointSize:
                    ui.font(
                        14,
                        root.viewportWidth,
                        root.viewportHeight
                    )

                elide: Text.ElideRight
            }
        }

        MouseArea {
            id: cardMouse

            anchors.fill: parent

            preventStealing: true

            drag.target: card
            drag.axis: Drag.XAxis

            drag.minimumX:
                -root.deleteRevealWidth

            drag.maximumX: 0

            property bool dragging: false

            onPressed: {
                dragging = false
            }

            onPositionChanged: {
                if (
                    Math.abs(card.x) >
                    ui.size(
                        6,
                        root.viewportWidth,
                        root.viewportHeight
                    )
                ) {
                    dragging = true
                }
            }

            onReleased: {
                if (card.x <= -root.deleteThreshold) {
                    root.openSwipeRequested()
                } else {
                    root.closeSwipeRequested()
                }
            }

            onClicked: {
                if (dragging)
                    return

                if (
                    card.x <
                    -ui.size(
                        16,
                        root.viewportWidth,
                        root.viewportHeight
                    )
                ) {
                    root.closeSwipeRequested()
                    return
                }

                root.editRequested(root.noteId)
            }
        }
    }
}
