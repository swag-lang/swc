#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui, Pixel, Viewers

// Open a program report, inspect its structure tree, and jump to a byte offset.
#[Swag.TestTag("integration.application.journey")]
#test
{
    var journey: ScopeJourney
    journey.setup()
    let file = journey.copyData("viewer.console.exe", "sample-program.exe")
    let window = journey.window

    window.openFile(file)
    journey.waitForFile(file)
    Swag.require(window.choices[window.activeChoiceIndex].key == "binary")
    let report = assume cast(*Binary.Panel, window.currentView)
    Swag.require(report.hasPage and report.page.isLocallyVisible())
    Swag.require(not report.doc.report.overview.sections.isEmpty())

    report.showPage(false)
    Swag.require(report.list.isLocallyVisible() and not report.page.isLocallyVisible())
    report.setExpandedAll(true)
    Swag.require(report.goToTypedOffset("0x80"))
    Swag.require(report.list.selectedLine() != null)

    window.sendCommandEvent(ViewerCommands.Close)
    journey.waitFor("program returned to recent files", func|window|()->bool =>
        window.home.isLocallyVisible() and window.currentView == null and window.recent.count == 1)
}
