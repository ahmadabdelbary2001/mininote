import QtQuick 2.12
import QtQuick.Controls.Basic 2.12
import QtQuick.Layouts 1.15

import "../theme"

Dialog {
    id: root

    property int noteId: -1
    property string noteTitle: ""
    property string deleteError: ""

    property bool busy: false

    property real viewportWidth: 360
    property real viewportHeight: 640

    property color textPrimary: "#2D252B"
    property color textSecondary: "#6F676D"
    property color deleteColor: "#C62828"

    signal confirmDelete(int noteId)

    modal: true

    title: "Delete note?"

    width: Math.min(root.viewportWidth - 20, 520)

    x: (root.viewportWidth - width) / 2
    y: (root.viewportHeight - height) / 2

    padding: 22

    UiMetrics {
        id: ui
    }

    contentItem: ColumnLayout {
        spacing:
            ui.size(
                16,
                root.viewportWidth,
                root.viewportHeight
            )

        Text {
            Layout.fillWidth: true

            text: root.noteTitle

            color: root.textPrimary

            font.pointSize:
                ui.font(
                    18,
                    root.viewportWidth,
                    root.viewportHeight
                )

            font.weight: Font.DemiBold

            wrapMode: Text.WordWrap
        }

        Text {
            Layout.fillWidth: true

            text: "This note will be permanently deleted."

            color: root.textSecondary

            font.pointSize:
                ui.font(
                    16,
                    root.viewportWidth,
                    root.viewportHeight
                )

            wrapMode: Text.WordWrap
        }

        Text {
            Layout.fillWidth: true

            visible: root.deleteError.length > 0

            text: root.deleteError

            color: root.deleteColor

            font.pointSize:
                ui.font(
                    14,
                    root.viewportWidth,
                    root.viewportHeight
                )

            wrapMode: Text.WordWrap
        }

        ColumnLayout {
            Layout.fillWidth: true

            spacing:
                ui.size(
                    10,
                    root.viewportWidth,
                    root.viewportHeight
                )

            Button {
                id: confirmDeleteButton

                Layout.fillWidth: true

                implicitHeight:
                    ui.size(
                        58,
                        root.viewportWidth,
                        root.viewportHeight
                    )

                text: "Delete"

                enabled: !root.busy

                background: Rectangle {
                    radius:
                        ui.size(
                            8,
                            root.viewportWidth,
                            root.viewportHeight
                        )

                    color: confirmDeleteButton.pressed
                        ? "#A91F1F"
                        : "#C62828"

                    opacity:
                        confirmDeleteButton.enabled
                        ? 1.0
                        : 0.55
                }

                contentItem: Text {
                    text: confirmDeleteButton.text

                    color: "#FFFFFF"

                    font.pointSize:
                        ui.font(
                            17,
                            root.viewportWidth,
                            root.viewportHeight
                        )

                    font.weight: Font.DemiBold

                    horizontalAlignment:
                        Text.AlignHCenter

                    verticalAlignment:
                        Text.AlignVCenter

                    elide: Text.ElideRight
                }

                onClicked: {
                    root.deleteError = ""
                    root.confirmDelete(root.noteId)
                }
            }

            Button {
                id: cancelDeleteButton

                Layout.fillWidth: true

                implicitHeight:
                    ui.size(
                        58,
                        root.viewportWidth,
                        root.viewportHeight
                    )

                text: "Cancel"

                enabled: !root.busy

                background: Rectangle {
                    radius:
                        ui.size(
                            8,
                            root.viewportWidth,
                            root.viewportHeight
                        )

                    color: cancelDeleteButton.pressed
                        ? "#5F5F5F"
                        : "#757575"

                    opacity:
                        cancelDeleteButton.enabled
                        ? 1.0
                        : 0.55
                }

                contentItem: Text {
                    text: cancelDeleteButton.text

                    color: "#FFFFFF"

                    font.pointSize:
                        ui.font(
                            17,
                            root.viewportWidth,
                            root.viewportHeight
                        )

                    font.weight: Font.DemiBold

                    horizontalAlignment:
                        Text.AlignHCenter

                    verticalAlignment:
                        Text.AlignVCenter
                }

                onClicked: root.close()
            }
        }
    }
}
