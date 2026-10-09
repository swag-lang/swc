#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Pixel, Gui, Viewers

#test
{
    Table.registerTexts(&g_App)

    const Source = "name;note;value\r\nalpha;\"two; parts\";1\r\nbeta;\"two\"\" quotes\";2\r\ngamma;\"two\r\nlines\";3\r\n"
    let delimiter = Table.detectDelimiter("sample.csv", Source)
    Swag.assert(delimiter == ';')

    let document = expect Table.parseDocument(Source, delimiter)
    Swag.assert(document.columns.count == 3 and document.rows.count == 3)
    Swag.assert(document.columns[0] == "name" and document.columns[2] == "value")
    Swag.assert(document.rows[0].cells[1] == "two; parts")
    Swag.assert(document.rows[1].cells[1] == "two\" quotes")
    Swag.assert(document.rows[2].cells[1] == "two\nlines")
    Swag.assert(Table.detectDelimiter("sample.tsv", "a,b\tc\n1,2\t3") == '\t')

    // The summary names the delimiter the file actually uses, not a comma for every other one.
    Swag.assert(Table.delimiterKind(',') == "CSV" and Table.delimiterKind('\t') == "TSV")
    Swag.assert(Table.delimiterKind(';') == Table.texts().ui_SemicolonKind and Table.delimiterKind('|') == Table.texts().ui_PipeKind)
}

#test
{
    Table.registerTexts(&g_App)

    let document = expect Table.parseDocument(";second\n1;2;3\n", ';')
    Swag.assert(document.columns.count == 3 and document.rows.count == 1)
    Swag.assert(document.columns[0] == "Column 1" and
                document.columns[1] == "second" and
                document.columns[2] == "Column 3")

    discard catch Table.parseDocument("name,value\n\"unfinished", ',') as quoteError
    Swag.assert(quoteError != null)
}

#test
{
    let fileName = Gui.Testing.tempFilePath("scope-table-", ".csv")
    defer discard catch File.delete(fileName)
    expect File.writeAllBytes(fileName, "city,temp,condition\nParis,22,clear\nReykjavik,8,rain\nTokyo,29,humid\n")

    var host: Testing.HeadlessHost
    host.setup(760, 480)
    defer host.shutdown()

    var result = openTestViewer(Table.viewerPlugin(), &host.root, fileName, commandParent: &host.root)
    Swag.assert(result.view != null and
                result.commands == null and
                result.collectMatches != null and
                result.revealMatch != null and
                result.searchBounds != null and
                result.clearSearch != null)
    let view = assume cast(*Table.Panel, result.view)
    completeViewerBackgroundLoad(&host, &view.load)
    Swag.assert(view.list.isVirtual and view.list.lineCount() == 3 and view.list.header.items.count == 3)
    var line: ListLine
    view.fillLine(&line, 1)
    Swag.assert(line.itemAt(0).name.raw == "Reykjavik" and line.itemAt(2).name.raw == "rain")
    var matches: Array'Viewer.SearchMatch
    collectViewerMatches(result.collectMatches, "humid", &matches)
    let revealed = matches.count == 1 and result.revealMatch(matches[0], "humid")
    Swag.assert(revealed)
    Swag.assert(view.searchRow == 2 and
                view.searchColumn == 2 and
                view.searchOffset == 0 and
                view.searchLength == 5)
    var bounds: Math.Rectangle
    Swag.assert(result.searchBounds(matches[0], &bounds) and not bounds.isEmpty())
    result.clearSearch()
    Swag.assert(not result.searchBounds(matches[0], &bounds))
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
    Swag.assert(leading.start == 0 and leading.end <= Table.CellPreviewBytes)

    let focused = Table.cellPreviewRange(giant, 8 * 1024)
    Swag.assert(focused.start > 0 and focused.end - focused.start <= Table.CellPreviewBytes)
    Swag.assert(focused.start <= 8 * 1024 and focused.end >= 8 * 1024 + ("needle").count)

    var unicode = String.from("x")
    for 400 do
        unicode += "\U0001F642"
    let unicodeRange = Table.cellPreviewRange(unicode)
    Swag.assert(Utf8.isValid(unicode.toSlice()[unicodeRange.start until unicodeRange.end]))

    var view: Table.Panel
    view.document.columns.add("payload")
    var row: Table.Row
    row.cells.add(#move giant)
    view.document.rows.add(#move row)

    var line: ListLine
    view.fillLine(&line, 0)
    let displayed = line.itemAt(0).name.raw.toString()
    Swag.assert(displayed.count <= Table.CellPreviewBytes)
}

// Generated headings follow the language; authored labels and selected rows remain intact.
#test
{
    var host: Testing.HeadlessHost
    host.setup(640, 360)
    defer
    {
        discard catch host.app.setLanguage(ReferenceLanguage)
        host.shutdown()
    }

    Table.registerTexts(&host.app)
    let document = expect Table.parseDocument(";Column 2\nfirst;second;third\n", ';')
    let view     = Table.Panel.createDocument(&host.root, document)
    var details: String
    view.userData = &details
    view.services.reportDetails = func(wnd, value) { cast(*String, wnd.userData!)[] = value }
    view.list.selectLine(0)
    let list       = view.list
    let oldHeading = String.from(view.list.header.items[0]!.name.raw)
    expect host.app.setLanguage("fr")
    host.notify(.LanguageChanged)
    Swag.assert(view.list.header.items[0]!.name.raw == Format.toString(Table.texts().ui_Column, 1))
    Swag.assert(view.list.header.items[0]!.name.raw != oldHeading)
    Swag.assert(view.list.header.items[1]!.name.raw == "Column 2")
    Swag.assert(view.list.header.items[2]!.name.raw == Format.toString(Table.texts().ui_Column, 3))
    Swag.assert(Utf8.contains(details, Table.texts().ui_Row))
    Swag.assert(Utf8.startsWith(details, Table.texts().ui_SemicolonKind) and not Utf8.contains(details, "CSV"))
    Swag.assert(view.list == list and view.list.isLineSelected(0) and view.document.rows[0].cells[1] == "second")
    expect host.app.setLanguage(ReferenceLanguage)
    host.notify(.LanguageChanged)
    Swag.assert(view.list.header.items[0]!.name.raw == oldHeading and view.list.isLineSelected(0))
}

#[Swag.TestTag("golden")]
#test
{
    let fileName = Gui.Testing.tempFilePath("scope-table-golden-", ".tsv")
    defer discard catch File.delete(fileName)
    expect File.writeAllBytes(fileName, "Name\tLanguage\tFiles\tStatus\nCore\tSwag\t148\tReady\nGui\tSwag\t203\tReady\nSwag Scope\tSwag\t61\tActive\n")

    var host: Testing.HeadlessHost
    host.setup(900, 560)
    defer host.shutdown()
    host.theme.setSwagDark()
    host.theme.metrics.surfaceWnd_ShadowSize   = 0
    host.theme.metrics.surfaceWnd_CornerRadius = 0
    host.notify(.ThemeChanged)

    var result = openTestViewer(Table.viewerPlugin(), &host.root, fileName, commandParent: &host.root)
    Swag.assert(result.view != null)
    let view = assume cast(*Table.Panel, result.view)
    completeViewerBackgroundLoad(&host, &view.load)
    view.dockStyle = .Center

    host.root.applyLayout()
    host.settleAnimations(&host.root, 4)
    var image = host.render(&host.root)
    Pixel.Testing.assertImageGolden(&image, "viewer.table.document")
}
