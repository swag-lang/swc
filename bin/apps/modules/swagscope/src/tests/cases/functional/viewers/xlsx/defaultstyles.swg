#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui, Viewers

// Real producer defaults supply number formatting and paint to cells without a direct style.
#test
{
    let book  = expect Xlsx.Workbook.load(scopeTestDataPath("viewer.default-styles.xlsx"))
    let sheet = &book.sheets[0]
    Swag.require(sheet.cellAt({1, 1})!.text == "€18.50")
    Swag.require(sheet.cellAt({2, 1})!.text == "75.00")
    Swag.require(sheet.cellAt({3, 1})!.text == "€24.0")
    Swag.require(sheet.cellAt({4, 1})!.text == "25.0%")
    Swag.require(book.styles.look(sheet.cellAt({1, 0})!.style).font.size == 14)
    Swag.require(book.styles.look(sheet.cellAt({2, 0})!.style).font.bold)
    Swag.require(book.styles.look(sheet.cellAt({2, 1})!.style).fill == 0xFFF0EDF7)
    Swag.require(book.styles.look(sheet.cellAt({0, 1})!.style).fill == 0xFFE8F3EE)
}

// Cell XF zero is explicit, row defaults require customFormat, and implicit addresses inherit too.
#test
{
    let xml  = "<worksheet><cols><col min='1' max='3' style='1'/></cols><sheetData><row r='1' s='2' customFormat='1'><c r='A1'><v>1</v></c><c r='B1' s='0'><v>2</v></c><c r='C1' s='3'><v>3</v></c></row><row r='2' s='2' customFormat='0'><c><v>4</v></c></row><row r='3' s='2' customFormat='true'><c><v>5</v></c></row><row r='4' s='0' customFormat='true'><c><v>6</v></c></row></sheetData></worksheet>"
    let path = formattedWorkbookVariant("xl/worksheets/one.xml", "", xml, replacePart: true)
    defer discard catch File.delete(path)
    let book  = expect Xlsx.Workbook.load(path)
    let sheet = &book.sheets[0]
    Swag.require(sheet.cellAt({0, 0})!.style == 2)
    Swag.require(sheet.cellAt({0, 1})!.style == 0)
    Swag.require(sheet.cellAt({0, 2})!.style == 3)
    Swag.require(sheet.cellAt({1, 0})!.style == 1)
    Swag.require(sheet.cellAt({2, 0})!.style == 2)
    Swag.require(sheet.cellAt({3, 0})!.style == 0)
}

// Far-away style ranges remain bounded and never materialize empty rows or columns.
#test
{
    let xml  = "<worksheet><cols><col min='16384' max='16384' style='1'/></cols><sheetData><row><c><v>7</v></c></row></sheetData></worksheet>"
    let path = formattedWorkbookVariant("xl/worksheets/one.xml", "", xml, replacePart: true)
    defer discard catch File.delete(path)
    let book = expect Xlsx.Workbook.load(path)
    Swag.require(book.sheets[0].columns.count == 1 and book.sheets[0].rows.count == 1)
    Swag.require(book.sheets[0].cellAt({0, 0})!.style == 0)
}

// Malformed inherited style/range declarations cannot escape index bounds.
#test
{
    for column in ["<col min='0' max='1' style='1'/>", "<col min='2' max='1' style='1'/>", "<col min='1' max='16385' style='1'/>", "<col min='1' max='1' style='-1'/>"]
    {
        var error: Swag.Error
        discard catch Xlsx.SheetStyleDefaults.parse(column) as error
        Swag.require(error.value() is Errors.InvalidFormatError)
    }
}
