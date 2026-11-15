#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Viewers

// Common numeric formats display quantities rather than their unformatted stored scalars.
#test
{
    struct Case {code: string; stored: string; expected: string}
    let cases = [
        Case{"0.00", "12.5", "12.50"},
        Case{"#,##0.00", "1234567.895", "1,234,567.90"},
        Case{"0%", "0.255", "26%"},
        Case{"0.00%", "0.125", "12.50%"},
        Case{"\"$\"#,##0.00", "-1250.5", "-$1,250.50"},
        Case{"0.00;(0.00);\"—\"", "-12.5", "(12.50)"},
        Case{"0.00;(0.00);\"—\"", "0", "—"},
        Case{"0.00;[Red](0.00)", "-2", "(2.00)"},
        Case{"0.##", "1.5", "1.5"},
        Case{"0.##", "2", "2"},
        Case{"00000", "42", "00042"},
        Case{"0.0,,\" million\"", "1250000", "1.3 million"},
        Case{"[$€-407]#,##0.00", "2500", "€2,500.00"},
        Case{"0.00;", "-1", ""},
        Case{"General", "1.23E+09", "1.23E+09"},
        Case{"0.00\"%\"", "0.25", "0.25%"}]
    for test in cases
    {
        let formatted = Xlsx.NumberFormat{String.from(test.code)}.format(test.stored)
        Swag.require(not formatted.omitted and formatted.text == test.expected)
    }
}

// Excel's two date epochs and fictitious leap day preserve the spreadsheet's own date values.
#test
{
    let iso = Xlsx.NumberFormat{String.from("yyyy-mm-dd")}
    Swag.require(iso.format("0").text == "1900-01-00")
    Swag.require(iso.format("1").text == "1900-01-01")
    Swag.require(iso.format("59").text == "1900-02-28")
    Swag.require(iso.format("60").text == "1900-02-29")
    Swag.require(iso.format("61").text == "1900-03-01")
    Swag.require(iso.format("0", true).text == "1904-01-01")
    Swag.require(iso.format("1462").text == iso.format("0", true).text)
    Swag.require(iso.format("2958465").text == "9999-12-31")
    Swag.require(iso.format("2957003", true).text == "9999-12-31")
    let day = Xlsx.NumberFormat{String.from("d-mmm-yyyy")}.format("45292")
    Swag.require(not day.omitted and day.text == "1-Jan-2024")
}

// Time formats distinguish minute tokens from months and support elapsed hours.
#test
{
    struct Case {code: string; stored: string; expected: string}
    let cases = [
        Case{"h:mm", "0.5", "12:00"},
        Case{"h:mm:ss AM/PM", "0.75", "6:00:00 PM"},
        Case{"h:mm AM/PM", "0", "12:00 AM"},
        Case{"[h]:mm:ss", "1.5", "36:00:00"},
        Case{"mm:ss", "0.0625", "30:00"},
        Case{"yyyy-mm-dd h:mm:ss", "45292.5", "2024-01-01 12:00:00"},
        Case{"h:mm m/d/yy", "45292.5", "12:00 1/1/24"}]
    for test in cases
    {
        let formatted = Xlsx.NumberFormat{String.from(test.code)}.format(test.stored)
        Swag.require(not formatted.omitted and formatted.text == test.expected)
    }
}

// Unsupported conditions, fractions, excessive precision and damaged formats retain the raw value.
#test
{
    for code in ["[>=100]0;0", "# ?/?", "0.0000000000000", "\"unclosed", "0.00E+00", "[$-F800]dddd", "0.0.0", "0%%", "#,###", ".00", "0.#0", "#,##00"]
    {
        let formatted = Xlsx.NumberFormat{String.from(code)}.format("12.5")
        Swag.require(formatted.omitted and formatted.text == "12.5", Format.toString("format % produced %", code, formatted.text))
    }

    for value in ["not a number", "1e99", "NaN", "Infinity"]
    {
        let formatted = Xlsx.NumberFormat{String.from("0.00")}.format(value)
        Swag.require(formatted.omitted and formatted.text == value)
    }
}

// Style XFs resolve custom formats and inherited base formats without evaluating formulas.
#test
{
    let source  = """<styleSheet><numFmts><numFmt numFmtId="164" formatCode="&quot;$&quot;#,##0.00"/></numFmts>
                   <cellStyleXfs><xf numFmtId="9"/></cellStyleXfs><cellXfs><xf numFmtId="0"/><xf numFmtId="164"/>
                   <xf numFmtId="0" xfId="0" applyNumberFormat="0"/></cellXfs></styleSheet>"""
    let formats = expect Xlsx.CellFormats.parse(source)
    Swag.require((expect formats.format("12.5", 0)).text == "12.5")
    Swag.require((expect formats.format("12.5", 1)).text == "$12.50")
    Swag.require((expect formats.format("0.25", 2)).text == "25%")
    var error: Swag.Error
    discard catch formats.format("12.5", 99) as error
    Swag.require(error.value() is Errors.InvalidFormatError)
}

// Styles resolve through workbook relationships, including cached formulas and formatted dates.
#test
{
    let workbook = expect Xlsx.Workbook.load(scopeTestDataPath("viewer.formats.xlsx"))
    Swag.require(workbook.sheets.count == 2 and workbook.omittedFormats == 0)
    for displayed in ["$1,250.50", "12.50%", "(45.70)", "12,345", "00042", "1/1/24", "2026-11-15", "36:00:00", "12:00:00", "75.00%"] do
        Swag.require(Utf8.contains(workbook.sheets[0].html, displayed) or Utf8.contains(workbook.sheets[1].html, displayed))
    Swag.require(not Utf8.contains(workbook.sheets[0].html, "=3/4"))
}

// Real producer number formats turn budget amounts and calculated percentages into readable values.
#test
{
    let workbook = expect Xlsx.Workbook.load(scopeTestDataPath("viewer.monthly-budget.xlsx"))
    Swag.require(workbook.omittedFormats == 0)
    for displayed in ["$2,500.00", "$1,414", "62%"] do
        Swag.require(Utf8.contains(workbook.sheets[0].html, displayed))
}

// Repackages a producer-style workbook with one controlled XML change.
internal func formattedWorkbookVariant(part: string, before, after: string)->String
{
    let source  = scopeTestDataPath("viewer.formats.xlsx")
    let archive = expect Archive.Zip.load(source)
    var entries: Array'ZipFixtureEntry
    for item in archive.entries
    {
        var entry: ZipFixtureEntry
        entry.name  = item.path
        entry.plain = expect Archive.Zip.loadEntry(source, item)
        if item.path == part
        {
            var text = String.from(cast(string, entry.plain.toSlice()))
            text.replace(before, after)
            entry.plain.clear()
            entry.plain.add(text.toSlice())
        }

        entry.packed = entry.plain
        entries.add(entry)
    }

    let path = Gui.Testing.tempFilePath("scope-xlsx-formats-", ".xlsx")
    discard expect File.writeAllBytes(path, buildZipEntries(entries.toSlice()).toSlice())
    return path
}

// Unsupported numeric display codes leave the stored value intact and name the limitation.
#test
{
    let path = formattedWorkbookVariant("xl/styles/book.xml", "&quot;$&quot;#,##0.00", "# ?/?")
    defer discard catch File.delete(path)
    let workbook = expect Xlsx.Workbook.load(path)
    Swag.require(workbook.omittedFormats == 1)
    Swag.require(Utf8.contains(workbook.sheets[0].html, "1250.5"))
    Swag.require(Utf8.contains(workbook.sheets[0].html, Xlsx.texts().ui_FormatNotice))
    Swag.require(Utf8.contains(workbook.details(), "1 number formats not shown"))
}

// The workbook's 1904 date-system flag changes dates without changing stored values or formulas.
#test
{
    let path = formattedWorkbookVariant("xl/workbook.xml", "<sheets>", "<workbookPr date1904=\"true\"/><sheets>")
    defer discard catch File.delete(path)
    let workbook = expect Xlsx.Workbook.load(path)
    Swag.require(workbook.omittedFormats == 0)
    Swag.require(Utf8.contains(workbook.sheets[1].html, "1/2/28"))
}
