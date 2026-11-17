#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui, Gui.Testing, Viewers

// Authored dimensions, merges and hidden ranges are retained alongside formatted cached values.
#test
{
    let workbook = expect Xlsx.Workbook.load(scopeTestDataPath("viewer.geometry.xlsx"))
    let sheet    = &workbook.sheets[0]
    Swag.require(sheet.rowCount == 12 and sheet.columns.count == 4 and sheet.merges.count == 2)
    Swag.require(sheet.columns[0].width == 201 and sheet.columns[1].width == 117 and sheet.columns[2].hidden)
    Swag.require(Math.abs(sheet.rows[0].height - 136.0 / 3) < 0.01 and sheet.rows[4].hidden)
    Swag.require(sheet.cellAt({0, 2})!.covered and sheet.cellAt({0, 0})!.merge == 0)
    Swag.require(sheet.cellAt({11, 3})!.text == "$1,327.80" and sheet.cellAt({11, 3})!.formula == "SUM(D3:D6)")
    Swag.require(not Utf8.contains(sheet.readingHtml(), "Private adjustment") and not Utf8.contains(sheet.readingHtml(), "Internal note"))
    Swag.require(Utf8.contains(sheet.readingHtml(true), "Private adjustment") and Utf8.contains(sheet.readingHtml(true), "Internal note"))
}

// Native cell selection, copy and keyboard navigation skip hidden rows and columns.
#test
{
    var host: HeadlessHost
    let window = framedViewerWindow(&host, scopeTestDataPath("viewer.geometry.xlsx"), false)
    let panel  = assume cast(*Xlsx.Panel, window.currentView)
    let grid   = unwrap panel.grid
    grid.selectAddress({2, 1})
    Swag.require(grid.selected.label() == "B3" and grid.selectedText() == "$1,100.00")

    // The copied cell replaces what the clipboard held, a picture copied before included.
    var picture = Pixel.Image.create(2, 2, .BGRA8)
    picture.clear()
    Clipboard.addImage(picture)
    var copy = KeyEvent{kind: .Pressed, key: .C, modifiers: .Control}
    grid.sendEvent(&copy)
    Swag.require(Clipboard.getString() == "$1,100.00" and not Clipboard.hasImage())
    var right = KeyEvent{kind: .Pressed, key: .Right}
    grid.sendEvent(&right)
    Swag.require(grid.selected.label() == "D3")
    var down = KeyEvent{kind: .Pressed, key: .Down}
    grid.sendEvent(&down)
    grid.sendEvent(&down)
    Swag.require(grid.selected.label() == "D6")
    grid.selectAddress({7, 2})
    Swag.require(grid.selected.label() == "A7" and grid.selectedText() == "Bring receipts to the next meeting.")
    let merged = grid.cellRect({6, 0}, {7, 3})
    Swag.require(merged.width == 449 and merged.height == 40)
}

// A reader can reveal hidden ranges and change reading mode without switching sheets.
#test
{
    var host: HeadlessHost
    let window = framedViewerWindow(&host, scopeTestDataPath("viewer.geometry.xlsx"), true)
    let panel  = assume cast(*Xlsx.Panel, window.currentView)
    panel.grid!.selectAddress({3, 3})
    panel.setHiddenRanges(true)
    Swag.require(panel.sheet == 0 and panel.grid.columnOffsets[3] > panel.grid.columnOffsets[2])
    Swag.require(panel.grid.selected.label() == "D4")
    panel.setTextMode(true)
    Swag.require(panel.grid == null and panel.view != null and panel.view.documentStyle.followTheme)
    panel.setTextMode(false)
    Swag.require(panel.grid != null and
                 panel.view == null and
                 panel.sheet == 0 and
                 panel.grid.selected.label() == "D4")
    panel.setHiddenRanges(false)
    Swag.require(panel.grid.columnOffsets[3] == panel.grid.columnOffsets[2])
}

// Malformed or out-of-order coordinates and overlapping merges cannot silently shift data.
#test
{
    for body in ["<row r='2'><c r='A1'/></row>", "<row r='2'/><row r='1'/>", "<row r='1'><c r='B1'/><c r='A1'/></row>", "<row r='1'><c r='A1x'/></row>"]
    {
        let source = Format.toString("<worksheet><sheetData>%</sheetData></worksheet>", body)
        let path   = formattedWorkbookVariant("xl/worksheets/one.xml", "", source, replacePart: true)
        defer discard catch File.delete(path)
        var error: Swag.Error
        discard catch Xlsx.Workbook.load(path) as error
        Swag.require(error.value() is Errors.InvalidFormatError)
    }

    let source = "<worksheet><sheetData/><mergeCells><mergeCell ref='A1:C2'/><mergeCell ref='B2:D3'/></mergeCells></worksheet>"
    let path   = formattedWorkbookVariant("xl/worksheets/one.xml", "", source, replacePart: true)
    defer discard catch File.delete(path)
    var error: Swag.Error
    discard catch Xlsx.Workbook.load(path) as error
    Swag.require(error.value() is Errors.InvalidFormatError)
}
