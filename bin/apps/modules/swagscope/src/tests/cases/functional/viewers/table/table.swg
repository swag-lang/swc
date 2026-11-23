#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Pixel, Gui, Viewers

// A generated monthly survey table keeps its field labels and twelve realistic observations.
#test
{
    let source    = expect File.readAllText(scopeTestDataPath("viewer.field-observations.csv"))
    let delimiter = Table.detectDelimiter("viewer.field-observations.csv", source)
    let document  = expect Table.parseDocument(source, delimiter)
    Swag.require(document.columns.count == 6 and document.rows.count == 12)
    Swag.require(document.columns[0] == "site_id" and document.columns[4] == "conductivity_us_cm")
    Swag.require(document.rows[2].cells[0] == "north-marsh" and document.rows[2].cells[3] == "38")
    Swag.require(document.rows[6].cells[1] == "2026-05-18T09:10:00Z")
}

// Explorer shows the parsed table surface, using only the bounded source prefix.
#test
{
    let file     = scopeTestDataPath("viewer.field-observations.csv")
    let registry = createViewerPluginRegistry()
    var renderer = expect ThumbnailRenderer.create()
    let image    = expect renderThumbnail(&registry, &renderer, file)

    Swag.require(image.isValid() and Math.max(image.width, image.height) <= 256)
    Swag.require(image.width > image.height)
    Swag.require(image.pixelColor(4, 4).argb == Color.fromRgb(248, 249, 250).argb)
    Swag.require(image.pixelColor(50, 10).argb == Color.fromRgb(232, 235, 238).argb)
}

// Bytes beyond the preview budget cannot delay or invalidate the first rows.
#test
{
    let fileName = Gui.Testing.tempFilePath("scope-table-thumbnail-", ".csv")
    defer catch File.delete(fileName)

    var source: String = "city,value\nParis,22\n"
    for 3000 do
        source += "row,2\n"
    source += "\"unfinished"
    discard expect File.writeAllText(fileName, source)

    var service: ThumbnailService
    let image = expect service.render(fileName)
    Swag.require(image.isValid() and image.width == 256)
}

// A damaged text encoding leaves the shared file card available.
#test
{
    let fileName = Gui.Testing.tempFilePath("scope-table-invalid-", ".csv")
    defer catch File.delete(fileName)
    discard expect File.writeAllBytes(fileName, [0xFF'u8])

    var service: ThumbnailService
    let image = expect service.render(fileName)
    Swag.require(image.isValid() and image.width == 256)
}

#test
{
    Swag.require(Viewer.isByteRangeInBounds(4, 0, 4))
    Swag.require(Viewer.isByteRangeInBounds(4, 4, 0))
    Swag.require(not Viewer.isByteRangeInBounds(4, Swag.U64.Max, 1))
    Swag.require(not Viewer.isByteRangeInBounds(4, 1, Swag.U64.Max))
}

// A numeric kind uses its opening sample, while the information sheet counts later contradictory
// values across the whole in-memory table instead of silently treating them as empty quantities.
#test
{
    Table.registerTexts(&g_App)
    var source: String = "measurement\n"
    for index in 128 do
        source += Format.toString("%\n", index + 1)
    source += "unknown\n"
    var document = expect Table.parseDocument(source, ',')

    var host: Testing.HeadlessHost
    host.setup(640, 360)
    let view = Table.Panel.createDocument(&host.root, #move document)
    Swag.require(view.kinds.count == 1 and view.kinds[0] == .Integer)
    view.profileColumns()
    Swag.require(Utf8.contains(view.profileText(0), Format.toString(Table.texts().ui_Inconsistent, 1).toString()))
}

// Quantities align on the right; a word, or a cell with no digit at all, keeps the column textual.
#test
{
    Swag.require(Table.isNumericCell("148") and Table.isNumericCell("-3.5") and Table.isNumericCell("1,234 %"))
    Swag.require(not Table.isNumericCell("") and not Table.isNumericCell("-") and not Table.isNumericCell("v2"))
}

// A quantity reads the same whether it is written plainly or with spaces, a percent sign, or a
// comma grouping thousands or marking decimals.
#test
{
    var value: f64
    Swag.require(Table.quantityOf("-3.25", &value) and value == -3.25)
    Swag.require(Table.quantityOf("1,5", &value) and value == 1.5)
    Swag.require(Table.quantityOf("1,234", &value) and value == 1234)
    Swag.require(Table.quantityOf("1,234.5", &value) and value == 1234.5)
    Swag.require(Table.quantityOf("12 %", &value) and value == 12)
    Swag.require(not Table.quantityOf("-", &value) and not Table.quantityOf("1.2.3", &value))
    Swag.require(not Table.quantityOf("1,12,345", &value) and
                 not Table.quantityOf("1,234.5,678", &value))
}

#test
{
    Table.registerTexts(&g_App)

    const Source = "name;note;value\r\nalpha;\"two; parts\";1\r\nbeta;\"two\"\" quotes\";2\r\ngamma;\"two\r\nlines\";3\r\n"
    let delimiter = Table.detectDelimiter("sample.csv", Source)
    Swag.require(delimiter == ';')

    let document = expect Table.parseDocument(Source, delimiter)
    Swag.require(document.columns.count == 3 and document.rows.count == 3)
    Swag.require(document.columns[0] == "name" and document.columns[2] == "value")
    Swag.require(document.rows[0].cells[1] == "two; parts")
    Swag.require(document.rows[1].cells[1] == "two\" quotes")
    Swag.require(document.rows[2].cells[1] == "two\nlines")
    Swag.require(Table.detectDelimiter("sample.tsv", "a,b\tc\n1,2\t3") == '\t')

    // The summary names the delimiter the file actually uses, not a comma for every other one.
    Swag.require(Table.delimiterKind(',') == "CSV" and Table.delimiterKind('\t') == "TSV")
    Swag.require(Table.delimiterKind(';') == Table.texts().ui_SemicolonKind and Table.delimiterKind('|') == Table.texts().ui_PipeKind)
}

#test
{
    Table.registerTexts(&g_App)

    let document = expect Table.parseDocument(";second\n1;2;3\n", ';')
    Swag.require(document.columns.count == 3 and document.rows.count == 1)
    Swag.require(document.columns[0] == "Column 1" and
                 document.columns[1] == "second" and
                 document.columns[2] == "Column 3")

    var quoteErrorOutcome: Swag.Error
    discard catch Table.parseDocument("name,value\n\"unfinished", ',') as quoteErrorOutcome
    let quoteError = quoteErrorOutcome.value()
    Swag.require(quoteError != null)
}

#test
{
    let fileName = Gui.Testing.tempFilePath("scope-table-", ".csv")
    defer discard catch File.delete(fileName)
    expect File.writeAllBytes(fileName, "city,temp,condition\nParis,22,clear\nReykjavik,8,rain\nTokyo,29,humid\n")

    var host: Testing.HeadlessHost
    host.setup(760, 480)

    var result = openTestViewer(Table.viewerPlugin(), &host.root, fileName, commandParent: &host.root)
    Swag.require(result.view != null and
                 result.commands == null and
                 result.collectMatches != null and
                 result.revealMatch != null and
                 result.searchBounds != null and
                 result.clearSearch != null)
    let view = assume cast(*Table.Panel, result.view)
    completeViewerBackgroundLoad(&host, &view.load)
    Swag.require(view.list.isVirtual and view.list.lineCount() == 3 and view.list.header.items.count == 3)
    var line: ListLine
    view.fillLine(&line, 1)
    Swag.require(line.itemAt(0).name.text == "Reykjavik" and line.itemAt(2).name.text == "rain")
    var matches: Array'Viewer.SearchMatch
    collectViewerMatches(result.collectMatches, "humid", &matches)
    let revealed = matches.count == 1 and result.revealMatch(matches[0], "humid")
    Swag.require(revealed)
    Swag.require(view.searchRow == 2 and
                 view.searchColumn == 2 and
                 view.searchOffset == 0 and
                 view.searchLength == 5)
    var bounds: Math.Rectangle
    Swag.require(result.searchBounds(matches[0], &bounds) and not bounds.isEmpty())
    view.searchOffset = Swag.U64.Max
    view.searchLength = 1
    Swag.require(not result.searchBounds(matches[0], &bounds))
    result.clearSearch()
    Swag.require(not result.searchBounds(matches[0], &bounds))
}

// A header click sorts the rows without moving them in the document: quantities as numbers, words
// in natural order, empty cells last, and search still reaches the line a row moved to.
#test
{
    let fileName = Gui.Testing.tempFilePath("scope-table-sort-", ".csv")
    defer discard catch File.delete(fileName)
    expect File.writeAllBytes(fileName, "name,size\nfile10,1 200\nfile9,\nfile2,35\nFile1,-4.5\n")

    var host: Testing.HeadlessHost
    host.setup(760, 480)
    var result = openTestViewer(Table.viewerPlugin(), &host.root, fileName, commandParent: &host.root)
    Swag.require(result.collectMatches != null and result.revealMatch != null)
    let view = assume cast(*Table.Panel, result.view)
    completeViewerBackgroundLoad(&host, &view.load)
    Swag.require(view.numeric[1] and not view.numeric[0])

    view.sortBy(1)
    Swag.require(view.order[0] == 3 and view.order[1] == 2 and view.order[2] == 0 and view.order[3] == 1)
    var line: ListLine
    view.fillLine(&line, 0)
    Swag.require(line.itemAt(0).name.text == "File1")

    view.sortBy(1)
    Swag.require(view.descending and view.order[0] == 0 and view.order[2] == 3 and view.order[3] == 1)

    view.sortBy(0)
    Swag.require(not view.descending and view.order[0] == 3 and view.order[1] == 2 and view.order[3] == 0)
    Swag.require(view.columnText(0) == "File1\nfile2\nfile9\nfile10" and view.columnText(1) == "-4.5\n35\n\n1 200", view.columnText(0))

    var matches: Array'Viewer.SearchMatch
    collectViewerMatches(result.collectMatches, "file10", &matches)
    Swag.require(matches.count == 1 and result.revealMatch(matches[0], "file10"))
    Swag.require(view.list.focusIndex == view.lineOfRow(0) and view.lineOfRow(0) == 3)

    view.list.unselectAll()
    view.list.setFocusedIndex(0)
    Swag.require(view.selectionText() == "File1\t-4.5\n")
    view.list.selectLine(1)
    view.list.selectLine(2)
    Swag.require(view.selectionText() == "file2\t35\nfile9\t\n")

    var quantity: f64
    Swag.require(Table.quantityOf("1,5", &quantity) and quantity == 1.5)
    Swag.require(Table.quantityOf("1,234.5", &quantity) and quantity == 1234.5)
    Swag.require(Table.quantityOf("12 %", &quantity) and quantity == 12)
}

// Year-first dates sort by their calendar fields even when the source mixes separators. A
// timestamp on the same day keeps its source-time order.
#test
{
    Swag.require(Table.dateKey("2025-12-31") < Table.dateKey("2026-01-02") and
                 Table.dateKey("2026-01-02") < Table.dateKey("2026/02/04"),
                 "date key ordering")
    var document = expect Table.parseDocument("day\n2026/02/04\n2025-12-31\n2026-01-02T09:00:00Z\n2026-01-02T08:00:00Z\n2026-01-02T08:00:00Z\n", ',')
    var host: Testing.HeadlessHost
    host.setup(760, 480)
    let view = Table.Panel.createDocument(&host.root, #move document)
    view.sortBy(0)
    Swag.require(view.kinds[0] == .Date)
    Swag.require(not view.numeric[0], "date column was marked numeric")
    Swag.require(view.order[0] == 1 and
                 view.order[1] == 3 and
                 view.order[2] == 4 and
                 view.order[3] == 2 and
                 view.order[4] == 0,
                 Format.toString("order: % % % % %", view.order[0], view.order[1], view.order[2], view.order[3], view.order[4]).toString())
    view.sortBy(0)
    Swag.require(view.order[0] == 0 and
                 view.order[1] == 2 and
                 view.order[2] == 3 and
                 view.order[3] == 4 and
                 view.order[4] == 1)

    var plainDates = expect Table.parseDocument("day\n2026-02-04\n2025-12-31\n", ',')
    let plainView  = Table.Panel.createDocument(&host.root, #move plainDates)
    Swag.require(plainView.kinds[0] == .Date and not plainView.numeric[0])
    plainView.sortBy(0)
    Swag.require(plainView.order[0] == 1 and plainView.order[1] == 0)
}

// A date that contradicts the first 128 rows remains visible at the end instead of masquerading
// as an enormous quantity or a valid calendar date.
#test
{
    Table.registerTexts(&g_App)
    var source: String = "day\n"
    for 128 do
        source += "2026-01-02\n"
    source += "2025-02-29\n"
    var document = expect Table.parseDocument(source.toString(), ',')
    var host: Testing.HeadlessHost
    host.setup(760, 480)
    let view = Table.Panel.createDocument(&host.root, #move document)
    Swag.require(view.kinds[0] == .Date)
    view.sortBy(0)
    Swag.require(view.order[view.order.count - 1] == 128)
    Swag.require(not Table.isDateCell("2025-02-29"))
    view.profileColumns()
    Swag.require(Utf8.contains(view.profileText(0), Format.toString(Table.texts().ui_Inconsistent, 1).toString()))
}

#test
{
    var giant: String
    giant.reserve(16 * 1024)
    for 8 * 1024 do
        giant += "a"
    giant += "needle"
    for 8 * 1024 do
        giant += "z"

    let leading = Table.cellPreviewRange(giant)
    Swag.require(leading.start == 0 and leading.end <= Table.CellPreviewBytes)

    let focused = Table.cellPreviewRange(giant, 8 * 1024)
    Swag.require(focused.start > 0 and focused.end - focused.start <= Table.CellPreviewBytes)
    Swag.require(focused.start <= 8 * 1024 and focused.end >= 8 * 1024 + ("needle").count)

    var unicode = String.from("x")
    for 400 do
        unicode += "\U0001F642"
    let unicodeRange = Table.cellPreviewRange(unicode)
    Swag.require(Utf8.isValid(unicode.toSlice()[unicodeRange.start until unicodeRange.end]))

    var view: Table.Panel
    view.document.columns.add("payload")
    var row: Table.Row
    row.cells.add(#move giant)
    view.document.rows.add(#move row)

    var line: ListLine
    view.fillLine(&line, 0)
    let displayed = line.itemAt(0).name.text.toString()
    Swag.require(displayed.count <= Table.CellPreviewBytes)
}

// Generated headings follow the language; authored labels and selected rows remain intact.
#test
{
    // The readout sink outlives the view that reports into it during teardown.
    var details: String
    var host:    Testing.HeadlessHost
    host.setup(640, 360)
    defer discard catch host.app.setLanguage(ReferenceLanguage)

    Table.registerTexts(&host.app)
    var document = expect Table.parseDocument(";Column 2\nfirst;second;third\n", ';')
    let view     = Table.Panel.createDocument(&host.root, #move document)
    view.userData = &details
    view.services.reportDetails = func(wnd, value) { cast(*String, unwrap wnd.userData)[] = value }
    view.list.selectLine(0)
    let list       = view.list
    let oldHeading = String.from(view.list.header.items[0]!.name.text)
    expect host.app.setLanguage("fr")
    host.notify(.LanguageChanged)
    Swag.require(view.list.header.items[0]!.name.text == Format.toString(Table.texts().ui_Column, 1))
    Swag.require(view.list.header.items[0]!.name.text != oldHeading)
    Swag.require(view.list.header.items[1]!.name.text == "Column 2")
    Swag.require(view.list.header.items[2]!.name.text == Format.toString(Table.texts().ui_Column, 3))

    // Structure and selection facts share the bottom reading line in the active language.
    Swag.require(Utf8.contains(details, Table.texts().ui_Row))
    Swag.require(Utf8.contains(details, Table.texts().ui_SemicolonKind) and Utf8.contains(details, "UTF-8"))
    Swag.require(view.list == list and view.list.isLineSelected(0) and view.document.rows[0].cells[1] == "second")
    expect host.app.setLanguage(ReferenceLanguage)
    host.notify(.LanguageChanged)
    Swag.require(view.list.header.items[0]!.name.text == oldHeading and view.list.isLineSelected(0))
}

// A colon and a number in the lens go to that row of a table as the row readout counts it, in the
// order on screen; a number past the last row offers nothing.
#test
{
    let fileName = Testing.tempFilePath("scope-table-rows-", ".csv")
    defer discard catch File.delete(fileName)
    var source: String = "name,value\n"
    for i in 300 do
        source += Format.toString("item %,%\n", i + 1, (i * 7) % 300)
    discard expect File.writeAllText(fileName, source)

    var host: Testing.HeadlessHost
    let window = framedViewerWindow(&host, fileName, false)
    let view   = assume cast(*Table.Panel, window.instances[window.activeChoiceIndex].view)
    view.sortBy(1)

    window.lens.open(":250")
    host.finishAnimations()
    let section = unwrap window.lens.results.sections[0]
    Swag.require(section.entries[0].title == Format.toString(Table.texts().ui_GoToRow, 250))
    section.entries[0].run!()
    window.lens.close()
    host.finishAnimations()
    Swag.require(view.list.focusIndex == 249)
    Swag.require(Utf8.contains(window.instances[window.activeChoiceIndex].details.toString(), Format.toString(Table.texts().ui_RowAt, 250).toString()))

    window.lens.open(":301")
    host.finishAnimations()
    Swag.require(window.lens.results.sections.isEmpty())
    window.lens.close()
    host.finishAnimations()
}

// Copied rows read back as the same values: a value holding a tab, a line break or a quote is
// quoted, its quotes doubled, and the lens copies with or without the column names.
#test
{
    let fileName = Testing.tempFilePath("scope-table-copy-", ".csv")
    defer discard catch File.delete(fileName)
    discard expect File.writeAllText(fileName, "name,note\nplain,été\n\"two\nlines\",\"say \"\"hi\"\"\"\n")

    var host: Testing.HeadlessHost
    let window = framedViewerWindow(&host, fileName, true)
    let view   = assume cast(*Table.Panel, window.instances[window.activeChoiceIndex].view)
    view.revealLine(1)
    Swag.require(view.selectionText() == "\"two\nlines\"\t\"say \"\"hi\"\"\"\n")

    // The copied rows replace what the clipboard held, a picture copied before included.
    var picture = Image.create(2, 2, .BGRA8)
    picture.clear()
    Clipboard.addImage(picture)
    var results: Lens.Results
    var entries = Viewer.LensEntries.create(&results, "Table", host.theme)
    view.revealLine(0)
    view.describeLens(&entries)
    for &entry in results.sections[0]!.entries where entry.title == Table.texts().ui_CopyRowsNames do
        entry.run!()
    Swag.require(Clipboard.getString() == "name\tnote\nplain\tété\n" and not Clipboard.hasImage())
}

// The information sheet profiles each column under its name: its kind, the range and the mean of
// its quantities, and its empty cells.
#test
{
    let fileName = Gui.Testing.tempFilePath("scope-table-profile-", ".csv")
    defer discard catch File.delete(fileName)
    discard expect File.writeAllText(fileName, "name,price,qty\nA,1.50,3\nB,,7\nC,2.25,\n")

    var host: Testing.HeadlessHost
    host.setup(640, 420)
    var result = openTestViewer(Table.viewerPlugin(), &host.root, fileName, commandParent: &host.root)
    let view   = assume cast(*Table.Panel, result.view)
    completeViewerBackgroundLoad(&host, &view.load)
    let sheet = InfoSheet.create(&host.root)
    view.describeInformation(sheet)
    let text = sheet.text()
    Swag.require(Utf8.contains(text, "Columns\nname\ntext\nprice\ndecimal · 1.50 to 2.25 · mean 1.88 · 1 empty"), text)
    Swag.require(Utf8.contains(text, "qty\ninteger · 3 to 7 · mean 5.00 · 1 empty"), text)
    Swag.require(Table.groupThousands(1.999, true) == "2.00" and Table.groupThousands(1234567, false) == "1 234 567")

    // A whole number is rounded rather than cut, and a value that rounds to nothing has no sign.
    Swag.require(Table.groupThousands(6.7, false) == "7" and Table.groupThousands(-1234.5, true) == "-1 234.50")
    Swag.require(Table.groupThousands(-0.001, true) == "0.00" and Table.groupThousands(-0.4, false) == "0")
}

// The foot sums the first column of quantities while the focus moves from row to row, and the
// column the table is sorted on as soon as it is sorted on one that holds quantities.
#test
{
    let fileName = Testing.tempFilePath("scope-table-sum-", ".csv")
    defer discard catch File.delete(fileName)
    discard expect File.writeAllText(fileName, "name,count,price\na,1,2.50\nb,2,1 000.25\nc,3,\n")

    var host: Testing.HeadlessHost
    let window = framedViewerWindow(&host, fileName, false)
    let view   = assume cast(*Table.Panel, window.instances[window.activeChoiceIndex].view)
    Swag.require(Utf8.contains(window.instances[window.activeChoiceIndex].details.toString(), "Σ count 6"))

    view.revealLine(2)
    let moved = window.instances[window.activeChoiceIndex].details.toString()
    Swag.require(Utf8.contains(moved, "Σ count 6") and Utf8.contains(moved, Format.toString(Table.texts().ui_RowAt, 3).toString()), moved)

    // Sorting moves the focused row to the line its price gives it, and the foot follows.
    view.revealLine(0)
    view.sortBy(2)
    let sorted = window.instances[window.activeChoiceIndex].details.toString()
    Swag.require(Utf8.contains(sorted, "Σ price 1 002.75") and Utf8.contains(sorted, Format.toString(Table.texts().ui_RowAt, 1).toString()), sorted)
    view.sortBy(2)
    let reversed = window.instances[window.activeChoiceIndex].details.toString()
    Swag.require(Utf8.contains(reversed, Format.toString(Table.texts().ui_RowAt, 2).toString()), reversed)
}

// Wide reading margins yield to the columns in a narrow cell and return when there is room.
#test
{
    var host: Testing.HeadlessHost
    host.setup(1200, 500)
    var document = expect Table.parseDocument("Name,Category,Measure,Sample\nNorth,Survey,120,May\n", ',')
    let view = Table.Panel.createDocument(&host.root, #move document)
    let columns = view.list.header.contentWidth()
    view.resize(columns + 2 * Table.PageMargin + 40, 420)
    Swag.require(view.padding.x == Table.PageMargin and view.padding.z == Table.PageMargin)
    view.resize(columns, 260)
    Swag.require(view.padding.x == view.themeMetrics().floating_Inset and view.padding.z == view.padding.x)
    view.resize(columns + 2 * Table.PageMargin + 40, 420)
    Swag.require(view.padding.x == Table.PageMargin and view.padding.z == Table.PageMargin)
}
