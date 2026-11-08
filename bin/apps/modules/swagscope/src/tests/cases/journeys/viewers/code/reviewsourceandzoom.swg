#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui, Pixel, Viewers

// Find a symbol in a source file, enlarge the code, then return to recent files.
#[Swag.TestTag("integration.application.journey")]
#test
{
    var journey: ScopeJourney
    journey.setup()
    let file = journey.copyData("sample.cpp", "review.cpp")
    let window = journey.window

    window.openFile(file)
    journey.waitForFile(file)
    Swag.require(window.choices[window.activeChoiceIndex].key == "code")
    let code = assume cast(*Code.Panel, window.currentView)
    Swag.require(code.zoomPercent == 100)

    window.sendCommandEvent(ViewerCommands.Find)
    window.searchBox.setText("doubled")
    journey.waitFor("source symbol matches", func|window|()->bool =>
        window.searchComplete and window.searchMatches.count == 3)
    code.setZoom(150)
    Swag.require(code.zoomPercent == 150 and (unwrap code.zoomLabel).text() == "150 %")
    window.sendCommandEvent(ViewerCommands.Close)
    journey.waitFor("source returned to recent files", func|window|()->bool =>
        window.home.isLocallyVisible() and window.currentView == null and window.recent.count == 1)
}
