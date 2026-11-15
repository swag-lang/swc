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

// Authored widths, row heights and merged reading notes form one worksheet in Encre.
#[Swag.TestTag("golden")]
#test
{
    picturedViewer(scopeTestDataPath("viewer.geometry.xlsx"), false, "viewer.xlsx.geometry.encre", 1040, 720)
}

// A freely licensed budget template retains its producer's cell geometry in Papier.
#[Swag.TestTag("golden")]
#test
{
    picturedViewer(scopeTestDataPath("viewer.monthly-budget.xlsx"), true, "viewer.xlsx.budget.paper", 1120, 720)
}

// Revealed hidden ranges and a selected total remain legible on a fractional-scale display.
#[Swag.TestTag("golden")]
#test
{
    var host: Testing.HeadlessHost
    host.setup(640, 440, dpiScale: 1.5)
    shipFrame(&host)
    host.theme.setLight()
    host.notify(.ThemeChanged)
    let window = ViewerWindow.create(&host.surfaceWnd, createViewerPluginRegistry())
    window.openFile(scopeTestDataPath("viewer.styles.xlsx"))
    completeQueuedViewerFile(&host, window)
    let panel = assume cast(*Xlsx.Panel, window.currentView)
    panel.setHiddenRanges(true)
    panel.grid!.selectAddress({11, 3})
    window.applyLayout()
    host.finishAnimations()
    var image = host.renderSettled(window)
    let grid = panel.grid
    let selected = grid.cellRect(grid.selected, grid.selected)
    Swag.require(selected.bottom() <= grid.clientRect().height + 1, Format.toString("selected bottom %; viewport %; origin %; scroll span %", selected.bottom(), grid.clientRect().height, grid.originY, grid.scroll.scrollSize.y))
    let point = grid.localToSurface(Math.Point{selected.horzCenter(), selected.y})
    let pixel = image.pixelColor(cast(s32, Math.round(point.x * grid.deviceScale())), cast(s32, Math.round(point.y * grid.deviceScale())))
    let arc = grid.themeColors().arc
    Swag.require(Math.abs(cast(s32, pixel.r) - arc.r) + Math.abs(cast(s32, pixel.g) - arc.g) + Math.abs(cast(s32, pixel.b) - arc.b) < 20,
                 Format.toString("selection at %,% missing; cell bottom %; viewport height %; grid y %; origin %; scroll span %", point.x, point.y, selected.bottom(), grid.clientRect().height, grid.surfaceRect().y, grid.originY, grid.scroll.scrollSize.y))
    assertScopeImageGolden(&image, "viewer.xlsx.revealed.hidpi.paper")
}

// Authored green headings, filled headers, a wrapped note and total rules retain their workbook colors.
#[Swag.TestTag("golden")]
#test
{
    var host: Testing.HeadlessHost
    let window = framedViewerWindow(&host, scopeTestDataPath("viewer.styles.xlsx"), false, 1040, 720)
    window.sendCommandEvent(ViewerCommands.Outline)
    window.applyLayout()
    host.finishAnimations()
    var image = host.renderSettled(window)
    assertScopeImageGolden(&image, "viewer.xlsx.styles.encre")
}
