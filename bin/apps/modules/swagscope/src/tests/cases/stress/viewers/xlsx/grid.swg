#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui, Gui.Testing, Viewers

// Excel's final row is addressable and copyable without allocating all intervening cell rows.
#test
{
    let source = "<worksheet><sheetData><row r='1048576'><c r='C1048576' t='inlineStr'><is><t>Far away</t></is></c></row></sheetData></worksheet>"
    let path   = formattedWorkbookVariant("xl/worksheets/one.xml", "", source, replacePart: true)
    defer discard catch File.delete(path)
    var host: HeadlessHost
    let window = framedViewerWindow(&host, path, false)
    let panel  = assume cast(*Xlsx.Panel, window.currentView)
    let grid   = unwrap panel.grid
    Swag.require(panel.workbook.sheets[0].rows.count == 1)
    grid.selectAddress({1048575, 2})
    Swag.require(grid.selected.label() == "C1048576" and grid.selectedText() == "Far away")
    Swag.require(grid.originY > 20_000_000 and grid.scroll.scrollSize.y <= 4_194_304)
    var image = host.renderSettled(window)
    Swag.require(image.width != 0)
    grid.scroll.setScrollPos(0, 0)
    window.resize(800, 500)
    window.applyLayout()
    Swag.require(grid.originY == 0 and grid.selected.label() == "C1048576")
}

// A million collapsed default rows still paint as two visible rows, and their addresses stay literal.
#test
{
    let source = "<worksheet><sheetFormatPr defaultRowHeight='0'/><sheetData><row r='1' ht='15'><c r='A1' t='inlineStr'><is><t>First</t></is></c></row><row r='1048576' ht='15'><c r='A1048576' t='inlineStr'><is><t>Last</t></is></c></row></sheetData></worksheet>"
    let path   = formattedWorkbookVariant("xl/worksheets/one.xml", "", source, replacePart: true)
    defer discard catch File.delete(path)
    var host: HeadlessHost
    let window = framedViewerWindow(&host, path, true)
    let panel  = assume cast(*Xlsx.Panel, window.currentView)
    let grid   = unwrap panel.grid
    Swag.require(grid.rowOffsets.back() == 40 and grid.rowAt(21) == 1048575)
    var image = host.renderSettled(window)
    Swag.require(image.width != 0)
}
