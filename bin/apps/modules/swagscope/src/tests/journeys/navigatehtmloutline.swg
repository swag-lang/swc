#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui, Pixel, Viewers

// Read an HTML outline, filter its headings, jump to a section, then return to the start.
#[Swag.TestTag("integration.application.journey")]
#test
{
    var journey: ScopeJourney
    journey.setup()
    let file = Path.combine(journey.root, "guide.html")
    expect File.writeAllText(file, "<html><body><h1>Guide</h1><div style='height:800px'></div><h2>Details</h2><div style='height:800px'></div></body></html>")
    let window = journey.window

    window.openFile(file)
    journey.waitForFile(file)
    Swag.require(window.choices[window.activeChoiceIndex].key == "html")
    window.sendCommandEvent(ViewerCommands.Outline)
    let outline = assume cast(*DocumentOutline, window.currentSidePanelHost!.children[0].children[0])
    journey.waitFor("outline shown", func|outline|()->bool => outline.isLocallyVisible() and
                                                         outline.rows.count == 2)

    outline.filterBox.setText("Details")
    Swag.require(outline.rows.count == 1)
    outline.filterBox.setText("")
    outline.list.selectLine(1)
    let html = assume cast(*Html.Panel, window.currentView)
    let scroll = assume cast(*ScrollWnd, html.view.children[0])
    journey.waitFor("details reached", func|scroll|()->bool => scroll.scrollPosition().y > 700)

    outline.list.selectLine(0)
    journey.waitFor("guide beginning", func|scroll|()->bool => scroll.scrollPosition().y < 2)
    window.sendCommandEvent(ViewerCommands.Outline)
    Swag.require(not window.currentSidePanelButton!.isChecked and
                 not window.currentSidePanelHost.isLocallyVisible())
}
