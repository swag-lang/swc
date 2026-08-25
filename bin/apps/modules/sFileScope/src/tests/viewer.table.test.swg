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
    @assert(result.view != null and result.commands == null and result.findText != null)
    @assert(result.details.indexOf("3 rows") != Swag.U64.Max and result.details.indexOf("3 columns") != Swag.U64.Max)

    let view = cast(*TableViewer) result.view!
    @assert(view.list.isVirtual and view.list.lineCount() == 3 and view.list.header.items.count == 3)
    var line: ListLine
    view.fillLine(&line, 1)
    @assert(line.itemAt(0).name.raw == "Reykjavik" and line.itemAt(2).name.raw == "rain")
    @assert(view.findText("humid") and view.searchRow == 2 and view.searchColumn == 2)
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
    view.dockStyle = .Center

    host.root.applyLayout()
    host.settleAnimations(&host.root, 4)
    var image = host.render(&host.root)
    Pixel.Testing.assertImageGolden(&image, "viewer.table.document")
}
