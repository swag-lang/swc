#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui, Gui.Testing, Viewers

// Workbook view state and hidden sheets stay separate from readable sheet content.
#test
{
    let workbook = expect Xlsx.Workbook.load(scopeTestDataPath("viewer.navigation.xlsx"))
    Swag.require(workbook.sheets.count == 3 and workbook.activeSheet == 2 and workbook.hiddenSheets == 1)
    Swag.require(workbook.cells == 6 and workbook.sheets[1].hidden)
    Swag.require(workbook.sheets[2].name == "Notes & plans" and workbook.sheets[2].cells == 2)
    Swag.require(not Utf8.contains(workbook.sheets[0].readingHtml(), "Intermediate result"))
}

// Arrows, keyboard and outline switch only visible sheets; ordinary page keys still scroll.
#test
{
    var host: HeadlessHost
    let window = openFramedViewerWindow(&host, scopeTestDataPath("viewer.navigation.xlsx"), false)
    let view   = assume cast(*Xlsx.Panel, window.currentView)
    Swag.require(view.sheet == 2 and view.visible.count == 2 and view.sheetLabel.text() == "2 / 2")
    Swag.require(view.gridHost!.children.count == 1 and Utf8.contains(window.readingLine.details.text(), "Notes & plans"))
    Swag.require(not view.nextButton.isEnabled() and view.previousButton.isEnabled())
    var page = KeyEvent{kind: .Pressed, key: .PageUp}
    Swag.require(not view.hookOnChildEvent!(unwrap view.grid, &page) and view.sheet == 2)
    page.modifiers = .Control
    Swag.require(view.hookOnChildEvent(view.grid, &page) and view.sheet == 0)
    view.turn(-1)
    view.showSheet(999)
    view.showSheet(1)
    Swag.require(view.sheet == 0 and not view.previousButton.isEnabled())
    view.outline.list.selectLine(1)
    Swag.require(view.sheet == 2)
    view.setShowHidden(true)
    Swag.require(view.visible.count == 3 and view.sheet == 2)
    view.turn(-1)
    Swag.require(view.sheet == 1 and view.sheetLabel.text() == "2 / 3")
    Swag.require(view.outline.rowTitles[1] == "Calculations (hidden)")
    view.setShowHidden(false)
    Swag.require(view.sheet == 0 and view.visible.count == 2)
}

// A workbook with no visible sheet waits for an explicit reveal, including veryHidden sheets.
#test
{
    let path = formattedWorkbookVariant("xl/workbook.xml", " sheetId=", " state=\"veryHidden\" sheetId=")
    defer discard catch File.delete(path)
    var host: HeadlessHost
    let window = openFramedViewerWindow(&host, path, true)
    let view   = assume cast(*Xlsx.Panel, window.currentView)
    Swag.require(not window.viewerBar.isLocallyVisible() and window.documentPanel.margin.w == 0)
    Swag.require(view.grid == null and view.visible.isEmpty() and view.status.text() == Xlsx.texts().ui_AllHidden)
    Swag.require(not view.previousButton.isEnabled() and not view.nextButton.isEnabled())
    view.setShowHidden(true)
    Swag.require(view.grid != null and view.sheet == 0 and view.visible.count == 2)
    Swag.require(window.viewerBar.isLocallyVisible() and view.gridHost!.margin.w == view.themeMetrics().floating_Inset)
    view.setShowHidden(false)
    Swag.require(view.grid == null and view.sheet == Swag.U64.Max)
}

// Sheet labels and translated details fit the minimum reading window in every shipped language.
#test
{
    var host: HeadlessHost
    let window = openFramedViewerWindow(&host, scopeTestDataPath("viewer.navigation.xlsx"), true, 560, 400)
    defer discard catch host.app.setLanguage(ReferenceLanguage)
    let view = assume cast(*Xlsx.Panel, window.currentView)
    view.setShowHidden(true)
    view.showSheet(1)
    for language in Gui.languages()
    {
        expect host.app.setLanguage(language.tag)
        window.applyLayout()
        Swag.require(view.sheet == 1 and view.sheetLabel.text() == "2 / 3")
        Swag.require(not Utf8.startsWith(Xlsx.texts().ui_Cells, "="))
        Swag.require(view.previousButton.toolTip == Xlsx.texts().ui_Previous)
        Testing.assertContentFits(view)
    }
}

// A colon and a cell address in the lens select that cell of the sheet in view, from the reading
// text too, and an address that is not one offers nothing.
#test
{
    var host: HeadlessHost
    let window = openFramedViewerWindow(&host, scopeTestDataPath("viewer.monthly-budget.xlsx"), true)
    let view   = assume cast(*Xlsx.Panel, window.currentView)
    view.setTextMode(true)

    window.lens.open(":c5")
    host.finishAnimations()
    let section = unwrap window.lens.results.sections[0]
    Swag.require(section.entries[0].title == Format.toString(Xlsx.texts().ui_GoToCell, "C5"))
    section.entries[0].run!()
    window.lens.close()
    host.finishAnimations()
    let grid = unwrap view.grid
    Swag.require(not view.textMode and grid.hasSelection and grid.selected.row == 4 and grid.selected.column == 2)

    // An OpenDocument spreadsheet is read by the same workbook panel and answers alike.
    var odsHost: HeadlessHost
    let odsWindow = openFramedViewerWindow(&odsHost, scopeTestDataPath("viewer.ods"), true)
    odsWindow.lens.open(":a1")
    odsHost.finishAnimations()
    Swag.require((unwrap odsWindow.lens.results.sections[0]).entries[0].title == Format.toString(Xlsx.texts().ui_GoToCell, "A1"))
    odsWindow.lens.close()
    odsHost.finishAnimations()

    window.lens.open(":5c")
    host.finishAnimations()
    Swag.require(window.lens.results.sections.isEmpty())
    window.lens.close()
    host.finishAnimations()
}
