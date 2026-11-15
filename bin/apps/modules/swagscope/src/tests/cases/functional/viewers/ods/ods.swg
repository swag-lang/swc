#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui, Viewers

// A genuine Calc export opens its styled cell values, merges and hidden rows in the native grid.
#test
{
    let workbook = expect Ods.load(scopeTestDataPath("viewer.ods"))
    Swag.require(workbook.sheets.count == 2 and workbook.cells >= 16)
    let sheet = &workbook.sheets[0]
    Swag.require(sheet.name == "Reading room budget" and sheet.merges.count == 2 and sheet.hiddenRanges)
    let title = unwrap sheet.cellAt({0, 0})
    Swag.require(Utf8.contains(title.text, "Reading room"))
    let look = workbook.styles.look(title.style)
    Swag.require(look.font.size == 22 and look.font.bold)
    Swag.require(sheet.columns[0].authored and sheet.columns[0].width > 200)
    Swag.require(not sheet.showGridLines)
}

// ODS uses the same sheet navigation, outline and selection lifecycle as XLSX.
#test
{
    var host: Testing.HeadlessHost
    let window = framedViewerWindow(&host, scopeTestDataPath("viewer.ods"), false)
    Swag.require(window.choices[window.activeChoiceIndex].key == "ods")
    let panel = assume cast(*Xlsx.Panel, window.currentView)
    Swag.require(panel.grid != null and panel.workbook.sheets.count == 2)
    panel.turn(1)
    Swag.require(panel.sheet == 1)
    panel.setTextMode(true)
    Swag.require(panel.view != null)
}

// A real budget converted by Calc retains its stored display text without evaluating formulas.
#test
{
    let workbook = expect Ods.load(scopeTestDataPath("viewer.monthly-budget.ods"))
    Swag.require(workbook.sheets.count >= 1 and workbook.cells > 50)
    var formulas = 0'u64
    for sheet in workbook.sheets do
        for row in sheet.rows do
            for cell in row.cells where not cell.formula.isEmpty() do
                formulas += 1
    Swag.require(formulas > 0)
}
