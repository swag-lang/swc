#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui, Pixel

// Change the requested document while classification runs, then close another queued opening.
#[Swag.TestTag("integration.application.journey")]
#test
{
    var journey: ScopeJourney
    journey.setup()
    let pdf = journey.copyData("viewer.pdf", "A-document.pdf")
    let archive = journey.copyData("viewer.archive.zip", "B-archive.zip")
    let picture = journey.copyData("appicon.png", "C-picture.png")
    let window = journey.window

    window.openFile(pdf)
    journey.app.runFrame()
    window.openFile(archive)
    window.openFile(picture)
    journey.waitForFile(picture)
    Swag.require(window.pendingFile.isEmpty() and window.choices[window.activeChoiceIndex].key == "image")

    window.openFile(pdf)
    window.sendCommandEvent(ViewerCommands.Close)
    journey.waitFor("queued opening dismissed", func|window|()->bool => window.home.isLocallyVisible() and
                                                                    window.currentFile.isEmpty() and
                                                                    window.pendingFile.isEmpty() and
                                                                    not window.choiceLoad.started)
    Swag.require(window.currentView == null)
}
