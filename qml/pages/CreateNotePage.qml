import QtQuick 2.12
import QtQuick.Controls.Basic 2.12
import QtQuick.Layouts 1.15

import "../components"
import "../theme"

Page {
    id: root

    readonly property real pageMargin:
        ui.size(24, width, height)

    UiMetrics {
        id: ui
    }

    background:
        Rectangle {
            color: "#F5F5F5"
        }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        PageHeader {
            id: header

            Layout.fillWidth: true

            title: "New Note"

            busy: noteController.saving

            onBackRequested: {
                var view = root.StackView.view

                if (view && !noteController.saving)
                    view.pop()
            }
        }

        ScrollView {
            id: formScroll

            Layout.fillWidth: true
            Layout.fillHeight: true

            clip: true

            contentWidth:
                availableWidth

            NoteEditorForm {
                id: editor

                width:
                    formScroll.availableWidth

                viewportHeight:
                    root.height

                actionText: "Save"

                busy:
                    noteController.saving

                actionEnabled:
                    !noteController.saving

                onSubmitted: function(title, body) {
                    noteController.saveNote(title, body)
                }
            }
        }
    }

    function submit() {
        editor.submit()
    }

    Connections {
        target: noteController

        function onNoteSaved() {
            if (root.StackView.view)
                root.StackView.view.pop()
        }

        function onSaveFailed(message) {
            editor.showError(message)
        }

        function onValidationFailed(message) {
            editor.showError(message)
        }
    }
}
