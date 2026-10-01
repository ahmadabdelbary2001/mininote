import QtQuick 2.12
import QtQuick.Controls.Basic 2.12
import QtQuick.Layouts 1.15

import "../components"
import "../theme"

Page {
    id: root

    property int noteId: -1
    property bool loaded: false

    UiMetrics {
        id: ui
    }

    background:
        Rectangle {
            color: "#F5F5F5"
        }

    Component.onCompleted:
        loadNote()

    function loadNote() {
        if (noteId <= 0)
            return

        var note =
            noteController.getNote(noteId)

        if (!note || !note.id) {
            editor.showError(
                "This note could not be found"
            )
            return
        }

        editor.titleText = note.title
        editor.bodyText = note.body

        loaded = true
    }

    function submit() {
        editor.submit()
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        PageHeader {
            id: header

            Layout.fillWidth: true

            title: "Edit Note"

            busy:
                noteController.saving

            onBackRequested: {
                var view = root.StackView.view

                if (
                    view
                    && !noteController.saving
                ) {
                    view.pop()
                }
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

                actionText:
                    "Save changes"

                busy:
                    noteController.saving

                actionEnabled:
                    root.loaded
                    && !noteController.saving

                onSubmitted: function(title, body) {
                    noteController.updateNote(root.noteId, title, body)
                }
            }
        }
    }

    Connections {
        target: noteController

        function onNoteUpdated() {
            if (root.StackView.view)
                root.StackView.view.pop()
        }

        function onUpdateFailed(message) {
            editor.showError(message)
        }

        function onValidationFailed(message) {
            editor.showError(message)
        }
    }
}
