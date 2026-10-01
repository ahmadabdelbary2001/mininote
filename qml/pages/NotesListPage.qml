import QtQuick 2.12
import QtQuick.Controls.Basic 2.12
import QtQuick.Layouts 1.15

import "../components"
import "../theme"

Page {
    id: root

    readonly property color headerBackground: "#2C001E"
    readonly property color headerForeground: "#FFFFFF"
    readonly property color accent: "#77216F"
    readonly property color accentPressed: "#5E2750"
    readonly property color backgroundColor: "#F5F5F5"
    readonly property color cardColor: "#FFFFFF"
    readonly property color cardBorder: "#D8D3D7"
    readonly property color textPrimary: "#2D252B"
    readonly property color textSecondary: "#6F676D"
    readonly property color deleteColor: "#C62828"
    readonly property color deletePressed: "#9E1F1F"

    readonly property real uiScale:
        ui.scaleFor(width, height)

    readonly property real pageMargin:
        ui.size(24, width, height)

    readonly property real headerHeight:
        ui.size(78, width, height)

    readonly property real fabVisualSize:
        ui.size(100, width, height)

    readonly property real fabHitSize:
        ui.size(124, width, height)

    property int openedNoteId: -1

    UiMetrics {
        id: ui
    }

    background: Rectangle {
        color: root.backgroundColor
    }

    function closeSwipe() {
        root.openedNoteId = -1
    }

    function requestDelete(id, title) {
        root.closeSwipe()

        deleteDialog.noteId = id
        deleteDialog.noteTitle = title
        deleteDialog.deleteError = ""

        deleteDialog.open()
    }

    Rectangle {
        id: header

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top

        height: root.headerHeight

        color: root.headerBackground

        Text {
            anchors.left: parent.left
            anchors.leftMargin: root.pageMargin

            anchors.verticalCenter: parent.verticalCenter

            text: "MiniNotes"

            color: root.headerForeground

            font.pointSize:
                ui.font(
                    26,
                    root.width,
                    root.height
                )

            font.weight: Font.DemiBold
        }

        Text {
            anchors.right: parent.right
            anchors.rightMargin: root.pageMargin

            anchors.verticalCenter: parent.verticalCenter

            text:
                noteController.noteCount === 0
                ? ""
                : noteController.noteCount === 1
                    ? "1 note"
                    : noteController.noteCount + " notes"

            color: "#E6DDE4"

            font.pointSize:
                ui.font(
                    16,
                    root.width,
                    root.height
                )

            font.weight: Font.Medium
        }
    }

    ListView {
        id: notesView

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: header.bottom
        anchors.bottom: parent.bottom

        anchors.leftMargin: root.pageMargin
        anchors.rightMargin: root.pageMargin
        anchors.topMargin: root.pageMargin

        anchors.bottomMargin:
            root.pageMargin
            + root.fabHitSize
            + ui.size(
                14,
                root.width,
                root.height
            )

        clip: true

        spacing:
            ui.size(
                16,
                root.width,
                root.height
            )

        boundsBehavior:
            Flickable.StopAtBounds

        model: noteController.notesModel

        delegate: NoteCard {
            width: notesView.width

            viewportWidth: root.width
            viewportHeight: root.height

            noteId: model.noteId
            title: model.title
            body: model.body
            updatedAt: model.updatedAt

            opened:
                root.openedNoteId === model.noteId

            deleteEnabled:
                !noteController.deleting

            onOpenSwipeRequested: function() {
                root.openedNoteId = model.noteId
            }

            onCloseSwipeRequested: function() {
                root.openedNoteId = -1
            }

            onDeleteRequested: function(noteId, title) {
                root.requestDelete(noteId, title)
            }

            onEditRequested: function(noteId) {
                var view = root.StackView.view

                if (view) {
                    view.push(
                        "EditNotePage.qml",
                        {
                            "noteId": noteId
                        }
                    )
                }
            }
        }

        EmptyNotesState {
            anchors.centerIn: parent

            width: Math.min(
                parent.width,
                ui.size(
                    330,
                    root.width,
                    root.height
                )
            )

            height:
                ui.size(
                    290,
                    root.width,
                    root.height
                )

            visible:
                noteController.noteCount === 0

            viewportWidth: root.width
            viewportHeight: root.height

            textPrimary: root.textPrimary
            textSecondary: root.textSecondary
        }
    }

    FloatingActionButton {
        id: fab

        anchors.right: parent.right
        anchors.bottom: parent.bottom

        anchors.rightMargin:
            ui.size(
                10,
                root.width,
                root.height
            )

        anchors.bottomMargin:
            ui.size(
                10,
                root.width,
                root.height
            )

        visualSize: root.fabVisualSize
        hitSize: root.fabHitSize

        viewportWidth: root.width
        viewportHeight: root.height

        accent: root.accent
        accentPressed: root.accentPressed

        onClicked: {
            var view = root.StackView.view

            if (view)
                view.push("CreateNotePage.qml")
        }
    }

    DeleteNoteDialog {
        id: deleteDialog

        viewportWidth: root.width
        viewportHeight: root.height

        textPrimary: root.textPrimary
        textSecondary: root.textSecondary
        deleteColor: root.deleteColor

        busy: noteController.deleting

        onConfirmDelete: function(noteId) {
            noteController.deleteNote(noteId)
        }
    }

    Connections {
        target: noteController

        function onNoteDeleted(id) {
            if (id === deleteDialog.noteId)
                deleteDialog.close()
        }

        function onDeleteFailed(message) {
            deleteDialog.deleteError = message
            deleteDialog.open()
        }
    }
}
