#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui, Pixel

// Find text through native keys, click the next match, then navigate back with a shortcut.
#[Swag.TestTag("integration.desktop.input")]
#test
{
    var journey: ScopeJourney
    journey.setup()
    let file = Path.combine(journey.root, "notes.txt")
    expect File.writeAllText(file, "alpha beta alpha gamma alpha\n")
    let window = journey.window
    window.openFile(file)
    journey.waitForFile(file)

    var input = Testing.DesktopInput.create(&journey.app, journey.surface)
    input.shortcut(.F, .Control)
    journey.waitFor("native find shortcut", func|window|()->bool => window.searchBar.isLocallyVisible() and
                                                               window.searchBox.hasFocus())
    for key in [Input.Key.A, .L, .P, .H, .A] do
        input.shortcut(key, .None)
    journey.waitFor("native search text", func|window|()->bool => window.searchBox.text() == "alpha" and
                                                              window.searchComplete and window.searchMatches.count == 3)

    input.click(&window.searchNext.wnd)
    journey.waitFor("native next match", func|window|()->bool => window.searchIndex == 1)
    input.shortcut(.F3, .Shift)
    journey.waitFor("native previous match", func|window|()->bool => window.searchIndex == 0)
    input.shortcut(.Escape, .None)
    journey.waitFor("native dismiss", func|window|()->bool => not window.searchBar.isLocallyVisible())
}
