#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui, Viewers

func zoomFixturePath(name: string)->String => Path.combine(Path.combine(unwrap Path.directoryName(#curlocation.fileName), "datas"), name)

private var g_ReportedDetails: String

private func reportTestDetails(_: *Wnd, details: string) { g_ReportedDetails = details }

#test
{
    var host: Testing.HeadlessHost
    host.setup(800, 520)

    var textResult = openTestViewer(PlainText.viewerPlugin(), &host.root, zoomFixturePath("comprehensive.txt"))
    let text       = assume cast(*PlainText.Panel, textResult.view)
    defer text.setZoom(100)
    var wheel = MouseEvent{kind: .Wheel, delta: Math.Point{0, 120}, modifiers: .Control}
    Swag.assert(text.hookOnChildEvent!(text.editor, &wheel) and text.zoomPercent == 125)
    textResult = openTestViewer(PlainText.viewerPlugin(), &host.root, zoomFixturePath("comprehensive.txt"))
    Swag.assert(assume cast(*PlainText.Panel, textResult.view).zoomPercent == 125)

    var codeResult = openTestViewer(Code.viewerPlugin(), &host.root, zoomFixturePath("sample.cpp"))
    let code       = assume cast(*Code.Panel, codeResult.view)
    defer code.setZoom(100)
    wheel = {kind: .Wheel, delta: Math.Point{0, 120}, modifiers: .Control}
    Swag.assert(code.hookOnChildEvent!(code.editor, &wheel) and code.zoomPercent == 125)
    codeResult = openTestViewer(Code.viewerPlugin(), &host.root, zoomFixturePath("sample.cpp"))
    Swag.assert(assume cast(*Code.Panel, codeResult.view).zoomPercent == 125)

    var htmlResult = openTestViewer(Html.viewerPlugin(), &host.root, zoomFixturePath("viewer.html"))
    let html       = assume cast(*Html.Panel, htmlResult.view)
    defer html.setZoom(100)
    wheel = {kind: .Wheel, delta: Math.Point{0, 120}, modifiers: .Control}
    Swag.assert(html.hookOnChildEvent!(html.view, &wheel) and html.zoomPercent == 125)
    htmlResult = openTestViewer(Html.viewerPlugin(), &host.root, zoomFixturePath("viewer.html"))
    Swag.assert(assume cast(*Html.Panel, htmlResult.view).zoomPercent == 125)
}

#test
{
    let fileName = Testing.tempFilePath("scope-statistics-", ".md")
    defer discard catch File.delete(fileName)
    discard expect File.writeAllText(fileName, "Alpha beta\r\nthree\u00a0four\n")

    var host: Testing.HeadlessHost
    host.setup(800, 520)

    var services: Viewer.HostServices
    services.reportDetails = &reportTestDetails

    g_ReportedDetails.clear()
    var textResult = openTestViewer(PlainText.viewerPlugin(), &host.root, fileName, services: services)
    let text       = assume cast(*PlainText.Panel, textResult.view)
    completeTextStatistics(&host, text)
    Swag.assert(text.statistics.characters == 23)
    Swag.assert(Utf8.contains(g_ReportedDetails.toSlice(), "23 characters"))

    g_ReportedDetails.clear()
    let markdownResult = openTestViewer(MarkdownText.viewerPlugin(), &host.root, fileName, services: services)
    let zoomButton     = assume cast(*MarkdownText.ZoomButton, markdownResult.info!.children[0])
    completeViewerBackgroundLoad(&host, &zoomButton.statisticsLoad)
    Swag.assert(zoomButton.statistics.characters == 23)
    Swag.assert(g_ReportedDetails == "Markdown · UTF-8 · 2 lines · 4 words · 23 characters")
}
