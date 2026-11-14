#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui, Gui.Testing, Viewers

// Sheet and cell order follow the workbook and cell references, not ZIP member order.
#test
{
    let workbook = expect Xlsx.Workbook.load(scopeTestDataPath("viewer.xlsx"))
    Swag.require(workbook.sheets == 2 and workbook.cells == 6)
    Swag.require(Utf8.contains(workbook.html, "Summary &amp; totals"))
    Swag.require(Utf8.contains(workbook.html, "<tr><th></th><th>A</th><th>B</th><th>C</th></tr>"))
    Swag.require(Utf8.contains(workbook.html, "<td>Expense &amp; income</td><td>4</td><td>TRUE</td>"))
    Swag.require(Utf8.contains(workbook.html, "<td>Hello world</td>"))
    Swag.require(Utf8.contains(workbook.html, "<td>Second sheet</td><td></td><td>42</td>"))
}

// A workbook selects its reading surface before the generic archive fallback.
#test
{
    var host: HeadlessHost
    let window = framedViewerWindow(&host, scopeTestDataPath("viewer.xlsx"), false)
    Swag.require(window.choices[window.activeChoiceIndex].key == "xlsx")
    let view = assume cast(*Xlsx.Panel, window.instances[window.activeChoiceIndex].view)
    Swag.require(view.view != null and view.workbook.sheets == 2)
}

// A published budget template exercises a populated workbook with formulas and shared strings.
#test
{
    let workbook = expect Xlsx.Workbook.load(scopeTestDataPath("viewer.monthly-budget.xlsx"))
    Swag.require(workbook.sheets >= 1 and workbook.cells >= 20)
    Swag.require(Utf8.contains(workbook.html, "MONTHLY EXPENSES"))
    Swag.require(Utf8.contains(workbook.html, "Groceries"))
}

// Inline strings need no shared-string table, and a skipped column stays empty.
#test
{
    let workbook = expect Xlsx.Workbook.load(scopeTestDataPath("viewer.inline.xlsx"))
    Swag.require(workbook.sheets == 1 and workbook.cells == 2)
    Swag.require(Utf8.contains(workbook.html, "<tr><th style=\"padding-right:8px\">1</th>"))
    Swag.require(Utf8.contains(workbook.html, "<td>Safe &amp; sound</td><td></td><td>12.5</td>"))
}

// Missing relationship metadata is a damaged workbook, not an empty sheet.
#test
{
    var loadError: Swag.Error
    discard catch Xlsx.Workbook.load(scopeTestDataPath("viewer.damaged.xlsx")) as loadError
    Swag.require(loadError.value() is Errors.InvalidFormatError)
}

// A sparse worksheet retains its authored row and column coordinates.
#test
{
    let workbook = expect Xlsx.Workbook.load(scopeTestDataPath("viewer.sparse-rows.xlsx"))
    Swag.require(Utf8.contains(workbook.html, "<th>A</th><th>B</th><th>C</th>"))
    Swag.require(Utf8.contains(workbook.html,
                               "<tr><th style=\"padding-right:8px\">7</th><td>Safe &amp; sound</td><td></td><td>12.5</td></tr>"))
}

// Explicitly empty rows and cells keep their addresses without becoming a damaged sheet.
#test
{
    let workbook = expect Xlsx.Workbook.load(scopeTestDataPath("viewer.empty-cells.xlsx"))
    Swag.require(workbook.sheets == 1 and workbook.cells == 3)
    Swag.require(Utf8.contains(workbook.html, "<tr><th style=\"padding-right:8px\">3</th><td></td><td></td></tr>"))
    Swag.require(Utf8.contains(workbook.html, "<tr><th style=\"padding-right:8px\">4</th></tr>"))
}

// A formula without a cached result remains inspectable, including a shared-formula gap.
#test
{
    let workbook = expect Xlsx.Workbook.load(scopeTestDataPath("viewer.formulas.xlsx"))
    Swag.require(workbook.cells == 4)
    Swag.require(Utf8.contains(workbook.html,
                               "<td>Safe &amp; sound</td><td></td><td>=SUM(2,3)</td><td>[Formula result unavailable]</td><td>4</td>"))
}

// A column outside the bounded reading grid cannot be silently shifted into view.
#test
{
    var loadError: Swag.Error
    discard catch Xlsx.Workbook.load(scopeTestDataPath("viewer.wide-column.xlsx")) as loadError
    Swag.require(loadError.value() is Errors.UnsupportedFormatError)
}
