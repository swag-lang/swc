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

// Frozen authored header rows stay at the top while the worksheet body scrolls below them.
#test
{
    var worksheet = String.from("<worksheet><sheetViews><sheetView workbookViewId='0'><pane xSplit='1' ySplit='2' topLeftCell='B3' activePane='bottomRight' state='frozen'/></sheetView></sheetViews><sheetData><row r='1'><c r='A1' t='inlineStr'><is><t>Fiscal year</t></is></c><c r='T1' t='inlineStr'><is><t>Far cell</t></is></c></row>")
    for row in 2 until 121 do
        worksheet += Format.toString("<row r='%'/>", row)
    worksheet += "</sheetData></worksheet>"
    let path = formattedWorkbookVariant("xl/worksheets/one.xml", "", worksheet, replacePart: true)
    defer discard catch File.delete(path)
    let workbook = expect Xlsx.Workbook.load(path)
    Swag.require(workbook.sheets[0].frozenRows == 2 and workbook.sheets[0].frozenColumns == 1)

    var host: HeadlessHost
    let window  = framedViewerWindow(&host, path, false)
    let panel   = assume cast(*Xlsx.Panel, window.currentView)
    let grid    = unwrap panel.grid
    let frozenY = grid.cellRect({0, 0}, {0, 0}).y
    let frozenX = grid.cellRect({0, 0}, {0, 0}).x
    Swag.require(grid.originY == grid.rowOffsets[2] and
                 grid.originX == grid.columnOffsets[1] and
                 frozenY == 28 and
                 frozenX == 64)
    grid.originX = grid.columnOffsets[2]
    grid.syncScroll()
    Swag.require(grid.originX > grid.frozenWidth() and
                 grid.cellRect({0, 0}, {0, 0}).x == frozenX and
                 grid.cellRect({0, 2}, {0, 2}).x == 64 + grid.frozenWidth(),
                 Format.toString("A1 %, C1 %, origin %, freeze %", grid.cellRect({0, 0}, {0, 0}).x, grid.cellRect({0, 2}, {0, 2}).x, grid.originX, grid.frozenWidth()))
    grid.originY = grid.rowOffsets[5]
    grid.syncScroll()
    Swag.require(grid.originY > grid.rowOffsets[2] and grid.cellRect({0, 0}, {0, 0}).y == frozenY)
    Swag.require(grid.cellRect({2, 0}, {2, 0}).y == 28 + cast(f32, grid.rowOffsets[2] - grid.originY + grid.rowOffsets[2]))
    let hit = grid.addressAt({70, 35})
    Swag.require(hit.found and hit.address.row == 0 and hit.address.column == 0)
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

// A cell is painted as written: an angle bracket in its text gains no invisible companion.
#test
{
    let source = "<worksheet><sheetData><row r='1'><c r='A1' t='inlineStr'><is><t>a&lt;b</t></is></c></row></sheetData></worksheet>"
    let path   = formattedWorkbookVariant("xl/worksheets/one.xml", "", source, replacePart: true)
    defer discard catch File.delete(path)
    var host: HeadlessHost
    let window = framedViewerWindow(&host, path, false)
    let panel  = assume cast(*Xlsx.Panel, window.currentView)
    let grid   = unwrap panel.grid
    discard host.render(window)
    Swag.require(grid.scratch.text == "a<b", grid.scratch.text)
}

// The tooltip names the hovered cell, the anchor's text over a merged range, and nothing over the
// headers. It is rebuilt when the pointer enters another cell, not on each move inside one.
#test
{
    var host: HeadlessHost
    let window = framedViewerWindow(&host, scopeTestDataPath("viewer.geometry.xlsx"), false)
    let panel  = assume cast(*Xlsx.Panel, window.currentView)
    let grid   = unwrap panel.grid
    let price  = grid.localToSurface(grid.cellRect({2, 1}, {2, 1}).center())
    host.moveMouse(price)
    Swag.require(grid.toolTip == "$1,100.00", grid.toolTip)

    grid.toolTip = "unchanged"
    host.moveMouse(price + Math.Point{1, 1})
    Swag.require(grid.toolTip == "unchanged", grid.toolTip)

    host.moveMouse(grid.localToSurface(grid.cellRect({7, 2}, {7, 2}).center()))
    Swag.require(grid.toolTip == "Bring receipts to the next meeting.", grid.toolTip)
    host.moveMouse(grid.localToSurface(Math.Point{4, 4}))
    Swag.require(grid.toolTip.isEmpty(), grid.toolTip)
}
