#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui, Pixel, Viewers

// Follow a heading in a Markdown document and return to the first section.
#[Swag.TestTag("integration.application.journey")]
#test
{
    var journey: ScopeJourney
    journey.setup()
    let file = journey.copyData("comprehensive.md", "manual.md")
    let window = journey.window

    window.openFile(file)
    journey.waitForFile(file)
    Swag.require(window.choices[window.activeChoiceIndex].key == "markdown")
    window.sendCommandEvent(ViewerCommands.Outline)
    let outline = assume cast(*DocumentOutline, window.currentSidePanelHost!.children[0].children[0])
    journey.waitFor("Markdown outline", func|outline|()->bool => outline.isLocallyVisible() and outline.rows.count >= 7)

    outline.filterBox.setText("Search target")
    Swag.require(outline.rows.count == 1)
    outline.list.selectLine(0)
    let scroll = assume cast(*ScrollWnd, window.currentView!.children[0])
    journey.waitFor("target section", func|scroll|()->bool => scroll.scrollPosition().y > 0)
    let targetPosition = scroll.scrollPosition().y

    outline.filterBox.setText("")
    outline.list.selectLine(1)
    outline.list.selectLine(0)
    journey.waitFor("first section", func|scroll, targetPosition|()->bool =>
        scroll.scrollPosition().y < targetPosition)
    Swag.require(outline.list.selectedLine() == outline.rows[0])
}
