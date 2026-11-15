#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui, Viewers

// Ordered workbook cells and the reading column in Encre.
#[Swag.TestTag("golden")]
#test
{
    picturedViewer(scopeTestDataPath("viewer.xlsx"), false, "viewer.xlsx.sheets")
}

// Uncached formulas stay visible in a Papier workbook.
#[Swag.TestTag("golden")]
#test
{
    picturedViewer(scopeTestDataPath("viewer.formulas.xlsx"), true, "viewer.xlsx.formulas")
}

// Currency, percentages and dates are shown as authored values in Papier.
#[Swag.TestTag("golden")]
#test
{
    picturedViewer(scopeTestDataPath("viewer.formats.xlsx"), true, "viewer.xlsx.formats.paper")
}

// The date sheet is independently reachable beside the sheet list in Encre.
#[Swag.TestTag("golden")]
#test
{
    var host: Testing.HeadlessHost
    let window = framedViewerWindow(&host, scopeTestDataPath("viewer.formats.xlsx"), false)
    let view   = assume cast(*Xlsx.Panel, window.currentView)
    view.showSheet(1)
    window.sendCommandEvent(ViewerCommands.Outline)
    window.applyLayout()
    host.finishAnimations()
    var image = host.renderSettled(window)
    assertScopeImageGolden(&image, "viewer.xlsx.dates.encre")
}

// Hidden sheet names and navigation fit a small French reading window in Papier.
#[Swag.TestTag("golden")]
#test
{
    var host: Testing.HeadlessHost
    let window = framedViewerWindow(&host, scopeTestDataPath("viewer.navigation.xlsx"), true, 560, 400)
    defer discard catch host.app.setLanguage(ReferenceLanguage)
    expect host.app.setLanguage("fr")
    let view = assume cast(*Xlsx.Panel, window.currentView)
    view.setShowHidden(true)
    view.showSheet(1)
    window.applyLayout()
    host.finishAnimations()
    var image = host.renderSettled(window)
    assertScopeImageGolden(&image, "viewer.xlsx.hidden.fr.paper")
}
