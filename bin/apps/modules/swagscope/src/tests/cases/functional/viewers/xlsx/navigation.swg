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
    let window = framedViewerWindow(&host, scopeTestDataPath("viewer.navigation.xlsx"), false)
    let view   = assume cast(*Xlsx.Panel, window.currentView)
    Swag.require(view.sheet == 2 and view.visible.count == 2 and view.sheetLabel.text() == "2 / 2")
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
    let window = framedViewerWindow(&host, path, true)
    let view   = assume cast(*Xlsx.Panel, window.currentView)
    Swag.require(view.grid == null and view.visible.isEmpty() and view.status.text() == Xlsx.texts().ui_AllHidden)
    Swag.require(not view.previousButton.isEnabled() and not view.nextButton.isEnabled())
    view.setShowHidden(true)
    Swag.require(view.grid != null and view.sheet == 0 and view.visible.count == 2)
    view.setShowHidden(false)
    Swag.require(view.grid == null and view.sheet == Swag.U64.Max)
}

// Sheet labels and translated details fit the minimum reading window in every shipped language.
#test
{
    var host: HeadlessHost
    let window = framedViewerWindow(&host, scopeTestDataPath("viewer.navigation.xlsx"), true, 560, 400)
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
