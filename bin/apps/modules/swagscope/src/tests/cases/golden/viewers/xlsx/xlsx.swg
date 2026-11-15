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
