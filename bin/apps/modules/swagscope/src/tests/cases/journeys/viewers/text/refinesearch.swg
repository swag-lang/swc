#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui, Pixel

// Refine a live document search by word, case and pattern, then recover from an invalid pattern.
#[Swag.TestTag("integration.application.journey")]
#test
{
    var journey: ScopeJourney
    journey.setup()
    let file = Path.combine(journey.root, "notes.txt")
    expect File.writeAllText(file, "Cat cat scatter CAT\n")
    let window = journey.window

    window.openFile(file)
    journey.waitForFile(file)
    window.sendCommandEvent(ViewerCommands.Find)
    window.searchBox.setText("cat")
    journey.waitFor("all occurrences", func|window|()->bool => window.searchComplete and window.searchMatches.count == 4)

    window.sendCommandEvent(ViewerCommands.WholeWord)
    journey.waitFor("whole words", func|window|()->bool => window.searchComplete and window.searchMatches.count == 3)
    window.sendCommandEvent(ViewerCommands.MatchCase)
    journey.waitFor("case matched", func|window|()->bool => window.searchComplete and window.searchMatches.count == 1)

    window.sendCommandEvent(ViewerCommands.RegularExpression)
    window.searchBox.setText("c.t")
    journey.waitFor("pattern matched", func|window|()->bool => window.searchComplete and window.searchMatches.count == 1)
    window.searchBox.setText("(")
    Swag.require(not window.searchBox.isValid() and window.searchMatches.isEmpty())

    window.sendCommandEvent(ViewerCommands.RegularExpression)
    window.searchBox.setText("cat")
    journey.waitFor("search recovered", func|window|()->bool => window.searchBox.isValid() and
                                                            window.searchComplete and window.searchMatches.count == 1)
}
