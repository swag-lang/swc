#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui, Pixel

// Search a document, open one without search, then return and search again in the same window.
#[Swag.TestTag("integration.application.journey")]
#test
{
    var journey: ScopeJourney
    journey.setup()
    let text = Path.combine(journey.root, "notes.txt")
    expect File.writeAllText(text, "alpha beta alpha\nALPHA\n")
    let midi = journey.copyData("viewer.mid", "music.mid")
    let window = journey.window

    window.openFile(text)
    journey.waitForFile(text)
    window.sendCommandEvent(ViewerCommands.Find)
    window.searchBox.setText("alpha")
    journey.waitFor("three matches", func|window|()->bool => window.searchBar.isLocallyVisible() and
                                                        window.searchComplete and window.searchMatches.count == 3)
    window.sendCommandEvent(ViewerCommands.FindNext)
    journey.waitFor("second match", func|window|()->bool => window.searchIndex == 1 and window.searchCountLabel.text() == "2/3")

    window.openFile(midi)
    journey.waitForFile(midi)
    Swag.require(not window.searchBar.isLocallyVisible())

    window.openFile(text)
    journey.waitForFile(text)
    Swag.require(window.searchBar.isLocallyVisible() and window.searchBox.text().count == 0)
    window.searchBox.setText("alpha")
    journey.waitFor("search after return", func|window|()->bool => window.searchBar.isLocallyVisible() and
                                                              window.searchMatches.count == 3)
    Swag.require(window.searchBox.text() == "alpha")
}
