#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui, Pixel

// Edit a document outside Scope, reload it, and keep its search while the new bytes replace it.
#[Swag.TestTag("integration.application.journey")]
#test
{
    var journey: ScopeJourney
    journey.setup()
    let file = Path.combine(journey.root, "notes.txt")
    expect File.writeAllText(file, "alpha beta alpha\n")
    let window = journey.window

    window.openFile(file)
    journey.waitForFile(file)
    window.sendCommandEvent(ViewerCommands.Find)
    window.searchBox.setText("alpha")
    journey.waitFor("original matches", func|window|()->bool => window.searchComplete and window.searchMatches.count == 2)

    expect File.writeAllText(file, "alpha beta alpha gamma alpha\n")
    window.sendCommandEvent(ViewerCommands.Reload)
    journey.waitFor("reloaded matches", func|window|()->bool => window.currentView != null and
                                                            window.searchComplete and
                                                            window.searchMatches.count == 3)
    Swag.require(window.searchBox.text() == "alpha")
    Swag.require(window.searchBar.isLocallyVisible())
}
