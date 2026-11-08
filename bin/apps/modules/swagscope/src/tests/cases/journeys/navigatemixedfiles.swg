#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui, Pixel

// Read unlike neighboring files, wrap around the folder, and close back to the recent page.
#[Swag.TestTag("integration.application.journey")]
#test
{
    var journey: ScopeJourney
    journey.setup()
    let picture = journey.copyData("appicon.png", "A-picture.png")
    let text = journey.copyData("comprehensive.txt", "B-notes.txt")
    let table = journey.copyData("viewer.csv", "C-table.csv")
    let window = journey.window

    window.openFile(picture)
    journey.waitForFile(picture)
    Swag.require(window.choices[window.activeChoiceIndex].key == "image")

    window.sendCommandEvent(ViewerCommands.NextFile)
    journey.waitForFile(text)
    window.sendCommandEvent(ViewerCommands.NextFile)
    journey.waitForFile(table)
    window.sendCommandEvent(ViewerCommands.NextFile)
    journey.waitForFile(picture)
    window.sendCommandEvent(ViewerCommands.PreviousFile)
    journey.waitForFile(table)

    window.sendCommandEvent(ViewerCommands.Close)
    journey.waitFor("recent page", func|window|()->bool => window.home.isLocallyVisible() and window.currentView == null)
    Swag.require(window.recent.count == 3)
}
