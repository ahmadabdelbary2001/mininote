import QtQuick 2.12
import QtQuick.Controls.Basic 2.12
import QtQuick.Window 2.12

ApplicationWindow {
    id: window

    visible: true

    // Let Lomiri/Mir manage the application window instead of forcing
    // Window.FullScreen/showFullScreen(), which can make the app disappear
    // immediately on some Ubuntu Touch configurations.
    width: Screen.width > 0 ? Screen.width : 360
    height: Screen.height > 0 ? Screen.height : 760
    minimumWidth: 320
    minimumHeight: 480

    title: "MiniNotes"
    color: "#F5F5F5"

    StackView {
        id: stackView
        anchors.fill: parent
        initialItem: "pages/NotesListPage.qml"
    }

    readonly property bool __automation:
        typeof automationMode !== "undefined" && automationMode

    property var __automationPage: null
    property int __automationFailures: 0
    property int __automationInitialCount: 0

    function automationFail(message) {
        window.__automationFailures++
        console.log("AUTOMATION: **FAIL** " + message)
        automationFinished(true)
    }

    function findChildObj(item, name) {
        if (!item)
            return null

        if (item.objectName === name)
            return item

        for (var i = 0; i < item.children.length; ++i) {
            var result = findChildObj(item.children[i], name)
            if (result)
                return result
        }

        return null
    }

    Timer {
        id: automationTimer
        interval: 80
        repeat: true
        property int ticks: 0
        onTriggered: window.automationTick()
    }

    Component.onCompleted: {
        console.log(
            "MININOTES-GEOM"
            + " screen=" + Screen.width + "x" + Screen.height
            + " available=" + Screen.desktopAvailableWidth + "x" + Screen.desktopAvailableHeight
            + " dpr=" + Screen.devicePixelRatio
            + " window=" + window.width + "x" + window.height
        )

        console.log(
            "AUTOMATION-DEBUG context automationMode="
            + automationMode
            + " type=" + (typeof automationMode)
            + " gate=" + window.__automation
        )

        if (window.__automation)
            automationTimer.start()
    }

    function automationTick() {
        automationTimer.ticks++

        switch (automationTimer.ticks) {
        case 1: {
            console.log("AUTOMATION: begin")
            window.__automationInitialCount = noteController.noteCount
            var page = stackView.push("pages/CreateNotePage.qml")
            window.__automationPage = page
            break
        }

        case 2: {
            var p = window.__automationPage
            p.submit()

            var titleE = findChildObj(p, "titleError")
            var bodyE = findChildObj(p, "bodyError")

            if (titleE && bodyE && titleE.visible && bodyE.visible)
                console.log("AUTOMATION: validation-labels OK")
            else
                automationFail("validation-labels missing/invisible")

            if (noteController.noteCount !== window.__automationInitialCount) {
                automationFail(
                    "count grew after empty submit (now "
                    + noteController.noteCount + ")"
                )
            }
            break
        }

        case 3: {
            var page = window.__automationPage
            var titleF = findChildObj(page, "titleField")
            var bodyF = findChildObj(page, "bodyField")

            if (!titleF || !bodyF) {
                automationFail("title/body fields not found")
                return
            }

            titleF.text = "Test Note"
            bodyF.text = "Hello Ubuntu Touch\nالعربية 😀 ' \" \\ ;"
            page.submit()
            break
        }

        case 4: {
            if (noteController.noteCount === window.__automationInitialCount + 1) {
                console.log(
                    "AUTOMATION: saved OK count="
                    + noteController.noteCount
                )
                break
            }

            if (noteController.noteCount > window.__automationInitialCount + 1) {
                automationFail("count=" + noteController.noteCount)
                return
            }

            automationTimer.ticks--
            break
        }

        case 5: {
            if (stackView.depth === 1)
                console.log("AUTOMATION: auto-pop-after-save OK")
            else
                automationFail("depth=" + stackView.depth)

            automationFinished(false)
            break
        }

        default:
            if (automationTimer.ticks > 40)
                automationFail("timeout, tick=" + automationTimer.ticks)
        }
    }

    function automationFinished(failed) {
        automationTimer.stop()
        console.log(
            failed
                ? "AUTOMATION: RESULT FAIL"
                : "AUTOMATION: RESULT PASS"
        )
        Qt.quit()
    }

}
