import QtQuick 2.12
import QtQuick.Controls.Basic 2.12
import QtQuick.Layouts 1.15

import "../theme"

ColumnLayout {
    id: root

    property real viewportHeight: 760

    property alias titleText: titleField.text
    property alias bodyText: bodyField.text

    property alias titleField: titleField
    property alias bodyField: bodyField

    property bool attempted: false

    property bool actionEnabled: true
    property bool busy: false
    property string actionText: "Save"

    readonly property color textPrimary: "#333333"
    readonly property color textSecondary: "#777777"
    readonly property color accent: "#77216F"
    readonly property color errorColor: "#C1001E"

    readonly property real pageMargin:
        ui.size(24, width, viewportHeight)

    readonly property real controlHeight:
        ui.size(78, width, viewportHeight)

    signal submitted(string title, string body)

    UiMetrics {
        id: ui
    }

    spacing: ui.size(14, width, viewportHeight)

    Item {
        Layout.fillWidth: true
        Layout.preferredHeight:
            ui.size(12, root.width, root.viewportHeight)
    }

    Text {
        text: "Title"

        color: root.textSecondary

        font.pointSize:
            ui.font(18, root.width, root.viewportHeight)

        font.weight: Font.DemiBold

        Layout.fillWidth: true
        Layout.leftMargin: root.pageMargin
        Layout.rightMargin: root.pageMargin
    }

    TextField {
        id: titleField

        objectName: "titleField"

        Layout.fillWidth: true

        Layout.preferredHeight:
            root.controlHeight

        Layout.leftMargin: root.pageMargin
        Layout.rightMargin: root.pageMargin

        placeholderText: "Note title"

        font.pointSize:
            ui.font(20, root.width, root.viewportHeight)

        color: root.textPrimary

        padding:
            ui.size(18, root.width, root.viewportHeight)

        verticalAlignment: TextInput.AlignVCenter

        background: Rectangle {
            radius:
                ui.size(10, root.width, root.viewportHeight)

            color: "#FFFFFF"

            border.color:
                titleField.activeFocus
                    ? root.accent
                    : "#C9C9C9"

            border.width:
                titleField.activeFocus
                    ? 2
                    : 1
        }

        Keys.onReturnPressed:
            bodyField.forceActiveFocus()

        Keys.onEnterPressed:
            bodyField.forceActiveFocus()

        onTextEdited: {
            if (root.attempted)
                root.validate()
        }
    }

    Text {
        id: titleError

        objectName: "titleError"

        visible: false
        text: ""

        color: root.errorColor

        font.pointSize:
            ui.font(15, root.width, root.viewportHeight)

        wrapMode: Text.WordWrap

        Layout.fillWidth: true
        Layout.leftMargin: root.pageMargin
        Layout.rightMargin: root.pageMargin
    }

    Text {
        text: "Content"

        color: root.textSecondary

        font.pointSize:
            ui.font(18, root.width, root.viewportHeight)

        font.weight: Font.DemiBold

        Layout.fillWidth: true
        Layout.leftMargin: root.pageMargin
        Layout.rightMargin: root.pageMargin

        Layout.topMargin:
            ui.size(8, root.width, root.viewportHeight)
    }

    Rectangle {
        id: bodyFrame

        Layout.fillWidth: true

        Layout.preferredHeight:
            Math.max(
                ui.size(260, root.width, root.viewportHeight),
                Math.min(
                    root.viewportHeight * 0.42,
                    ui.size(400, root.width, root.viewportHeight)
                )
            )

        Layout.leftMargin: root.pageMargin
        Layout.rightMargin: root.pageMargin

        radius:
            ui.size(10, root.width, root.viewportHeight)

        color: "#FFFFFF"

        border.color:
            bodyField.activeFocus
                ? root.accent
                : "#C9C9C9"

        border.width:
            bodyField.activeFocus
                ? 2
                : 1

        clip: true

        Flickable {
            id: bodyFlick

            anchors.fill: parent
            anchors.margins: bodyFrame.border.width

            clip: true

            interactive:
                bodyField.activeFocus

            boundsBehavior:
                Flickable.StopAtBounds

            contentWidth: width

            contentHeight:
                Math.max(
                    height,
                    bodyField.height
                )

            function ensureCursorVisible() {
                var r = bodyField.cursorRectangle

                var margin =
                    ui.size(
                        10,
                        root.width,
                        root.viewportHeight
                    )

                var viewportTop =
                    bodyFlick.contentY + margin

                var viewportBottom =
                    bodyFlick.contentY
                    + bodyFlick.height
                    - margin

                var target =
                    bodyFlick.contentY

                if (r.y < viewportTop) {
                    target = r.y - margin
                } else if (
                    r.y + r.height > viewportBottom
                ) {
                    target =
                        r.y
                        + r.height
                        - bodyFlick.height
                        + margin
                }

                var maxY =
                    Math.max(
                        0,
                        bodyFlick.contentHeight
                        - bodyFlick.height
                    )

                bodyFlick.contentY =
                    Math.max(
                        0,
                        Math.min(maxY, target)
                    )
            }

            TextArea {
                id: bodyField

                objectName: "bodyField"

                width: bodyFlick.width

                height:
                    Math.max(
                        bodyFlick.height,
                        contentHeight
                        + topPadding
                        + bottomPadding
                        + ui.size(
                            4,
                            root.width,
                            root.viewportHeight
                        )
                    )

                placeholderText:
                    "Write your note..."

                font.pointSize:
                    ui.font(20, root.width, root.viewportHeight)

                color: root.textPrimary

                padding:
                    ui.size(
                        17,
                        root.width,
                        root.viewportHeight
                    )

                wrapMode: Text.Wrap
                textFormat: TextEdit.PlainText

                selectByMouse: false
                selectByKeyboard: true
                persistentSelection: false

                background: Rectangle {
                    color: "transparent"
                }

                onCursorRectangleChanged:
                    Qt.callLater(bodyFlick.ensureCursorVisible)

                onTextChanged: {
                    if (root.attempted)
                        root.validate()

                    Qt.callLater(
                        bodyFlick.ensureCursorVisible
                    )
                }

                onActiveFocusChanged: {
                    if (activeFocus)
                        Qt.callLater(
                            bodyFlick.ensureCursorVisible
                        )
                }
            }
        }
    }

    Text {
        id: bodyError

        objectName: "bodyError"

        visible: false
        text: ""

        color: root.errorColor

        font.pointSize:
            ui.font(15, root.width, root.viewportHeight)

        wrapMode: Text.WordWrap

        Layout.fillWidth: true
        Layout.leftMargin: root.pageMargin
        Layout.rightMargin: root.pageMargin
    }

    Rectangle {
        id: saveErrorBox

        objectName: "editorErrorBox"

        visible: false

        Layout.fillWidth: true

        Layout.preferredHeight:
            saveErrorLabel.implicitHeight
            + ui.size(
                30,
                root.width,
                root.viewportHeight
            )

        Layout.leftMargin: root.pageMargin
        Layout.rightMargin: root.pageMargin

        radius:
            ui.size(
                10,
                root.width,
                root.viewportHeight
            )

        color: "#FDECEA"
        border.color: "#E7C2C0"
        border.width: 1

        Text {
            id: saveErrorLabel

            anchors.fill: parent

            anchors.margins:
                ui.size(
                    13,
                    root.width,
                    root.viewportHeight
                )

            text: ""

            color: root.errorColor

            font.pointSize:
                ui.font(
                    15,
                    root.width,
                    root.viewportHeight
                )

            wrapMode: Text.WordWrap

            verticalAlignment:
                Text.AlignVCenter
        }
    }

    Rectangle {
        id: saveButton

        Layout.fillWidth: true

        Layout.preferredHeight:
            ui.size(
                74,
                root.width,
                root.viewportHeight
            )

        Layout.leftMargin: root.pageMargin
        Layout.rightMargin: root.pageMargin

        Layout.topMargin:
            ui.size(
                8,
                root.width,
                root.viewportHeight
            )

        radius:
            ui.size(
                12,
                root.width,
                root.viewportHeight
            )

        color:
            saveTap.pressed
                ? "#5E2750"
                : root.accent

        opacity:
            root.actionEnabled ? 1.0 : 0.55

        Text {
            anchors.centerIn: parent

            text: root.busy
                ? "Saving..."
                : root.actionText

            color: "#FFFFFF"

            font.pointSize:
                ui.font(
                    20,
                    root.width,
                    root.viewportHeight
                )

            font.weight: Font.DemiBold
        }

        TapHandler {
            id: saveTap

            enabled: root.actionEnabled

            onTapped:
                root.submit()
        }
    }

    Item {
        Layout.fillWidth: true

        Layout.preferredHeight:
            root.pageMargin
            + ui.size(
                8,
                root.width,
                root.viewportHeight
            )
    }

    function validate() {
        var valid = true

        if (titleField.text.trim().length === 0) {
            titleError.text = "Title is required"
            titleError.visible = true
            valid = false
        } else {
            titleError.visible = false
        }

        if (bodyField.text.trim().length === 0) {
            bodyError.text = "Content is required"
            bodyError.visible = true
            valid = false
        } else {
            bodyError.visible = false
        }

        return valid
    }

    function submit() {
        root.attempted = true

        if (!root.validate())
            return

        saveErrorBox.visible = false

        root.submitted(
            titleField.text,
            bodyField.text
        )
    }

    function showError(message) {
        saveErrorLabel.text = message
        saveErrorBox.visible = true
    }

    function clearError() {
        saveErrorLabel.text = ""
        saveErrorBox.visible = false
    }
}
