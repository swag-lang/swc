#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Pixel, Gui

#test
{
    registerTableStrings(&g_App)

    const Source = "name;note;value\r\nalpha;\"two; parts\";1\r\nbeta;\"two\"\" quotes\";2\r\ngamma;\"two\r\nlines\";3\r\n"
    let delimiter = detectTableDelimiter("sample.csv", Source)
    @assert(delimiter == ';')

    let document = expect parseTableDocument(Source, delimiter)
    @assert(document.columns.count == 3 and document.rows.count == 3)
    @assert(document.columns[0] == "name" and document.columns[2] == "value")
    @assert(document.rows[0].cells[1] == "two; parts")
    @assert(document.rows[1].cells[1] == "two\" quotes")
    @assert(document.rows[2].cells[1] == "two\nlines")
    @assert(detectTableDelimiter("sample.tsv", "a,b\tc\n1,2\t3") == '\t')
}

#test
{
    registerTableStrings(&g_App)

    let document = expect parseTableDocument(";second\n1;2;3\n", ';')
    @assert(document.columns.count == 3 and document.rows.count == 1)
    @assert(document.columns[0] == "Column 1" and document.columns[1] == "second" and document.columns[2] == "Column 3")

    discard catch parseTableDocument("name,value\n\"unfinished", ',') as quoteError
    @assert(quoteError != null)
}

#test
{
    let fileName = Gui.Testing.tempFilePath("filescope-table-", ".csv")
    defer discard catch File.delete(fileName)
    expect File.writeAllBytes(fileName, "city,temp,condition\nParis,22,clear\nReykjavik,8,rain\nTokyo,29,humid\n")

    var host: Testing.HeadlessHost
    host.setup(760, 480)
    defer host.shutdown()

    let request = ViewerRequest{&host.root, &host.root, fileName}
    var result: ViewerResult
    createTableViewer(&request, &result)
    @assert(result.view != null and result.commands == null and result.collectMatches != null and result.revealMatch != null and result.searchBounds != null and result.clearSearch != null)
    let view = cast(*TableViewer) result.view!
    completeViewerBackgroundLoad(&host, &view.load, view.loadTimer)
    @assert(view.list.isVirtual and view.list.lineCount() == 3 and view.list.header.items.count == 3)
    var line: ListLine
    view.fillLine(&line, 1)
    @assert(line.itemAt(0).name.raw == "Reykjavik" and line.itemAt(2).name.raw == "rain")
    var matches: Array'ViewerSearchMatch
    result.collectMatches!(result.view!, "humid", {}, &matches)
    @assert(matches.count == 1 and result.revealMatch!(result.view!, matches[0], "humid"))
    @assert(view.searchRow == 2 and view.searchColumn == 2 and view.searchOffset == 0 and view.searchLength == 5)
    var bounds: Math.Rectangle
    @assert(result.searchBounds!(result.view!, matches[0], &bounds) and !bounds.isEmpty())
    result.clearSearch!(result.view!)
    @assert(!result.searchBounds!(result.view!, matches[0], &bounds))
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

    let leading = tableCellPreviewRange(giant.toString())
    @assert(leading.start == 0 and leading.end <= TableCellPreviewBytes)

    let focused = tableCellPreviewRange(giant.toString(), 8 * 1024)
    @assert(focused.start > 0 and focused.end - focused.start <= TableCellPreviewBytes)
    @assert(focused.start <= 8 * 1024 and focused.end >= 8 * 1024 + @countof("needle"))

    var unicode = String.from("x")
    for 400 do
        unicode += "\U0001F642"
    let unicodeRange = tableCellPreviewRange(unicode.toString())
    @assert(Utf8.isValid(unicode.toSlice()[unicodeRange.start until unicodeRange.end]))

    var view: TableViewer
    view.document.columns.add("payload")
    var row: TableRow
    row.cells.add(#move giant)
    view.document.rows.add(#move row)

    var line: ListLine
    view.fillLine(&line, 0)
    let displayed = line.itemAt(0).name.raw.toString()
    @assert(@countof(displayed) <= TableCellPreviewBytes)
}

#test
{
    let fileName = Gui.Testing.tempFilePath("filescope-table-golden-", ".tsv")
    defer discard catch File.delete(fileName)
    expect File.writeAllBytes(fileName, "Name\tLanguage\tFiles\tStatus\nCore\tSwag\t148\tReady\nGui\tSwag\t203\tReady\nsFileScope\tSwag\t61\tActive\n")

    var host: Testing.HeadlessHost
    host.setup(900, 560)
    defer host.shutdown()
    host.theme.setSwagDark()
    host.theme.metrics.surfaceWnd_ShadowSize   = 0
    host.theme.metrics.surfaceWnd_CornerRadius = 0
    host.notify(.ThemeChanged)

    let request = ViewerRequest{&host.root, &host.root, fileName}
    var result: ViewerResult
    createTableViewer(&request, &result)
    @assert(result.view != null)
    let view = cast(*TableViewer) result.view!
    completeViewerBackgroundLoad(&host, &view.load, view.loadTimer)
    view.dockStyle = .Center

    host.root.applyLayout()
    host.settleAnimations(&host.root, 4)
    var image = host.render(&host.root)
    Pixel.Testing.assertImageGolden(&image, "viewer.table.document")
}
