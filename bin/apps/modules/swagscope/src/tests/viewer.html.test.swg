#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Pixel, Gui

func htmlViewerFixturePath()->String
{
    return Path.combine(Path.combine(Path.directoryName(#curlocation.fileName)!, "datas"), "viewer.html")
}

func finishHtmlViewer(host: *Testing.HeadlessHost, result: *ViewerSession)
{
    var attempts: u32
    while result.isLoading!(result.view!) and attempts < 100
    {
        Threading.Thread.sleep(5'ms)
        host.app.runFrame()
        attempts += 1
    }
    Swag.assert(!result.isLoading!(result.view!))
}

// The viewer remains a thin ABI adapter around the reusable GUI control.
#test
{
    let fileName = htmlViewerFixturePath()

    var host: Testing.HeadlessHost
    host.setup(640, 360)
    defer host.shutdown()

    var result = openTestViewer(htmlViewerPlugin(), &host.root, fileName.toString(), commandParent: &host.root)
    Swag.assert(result.view != null)
    Swag.assert(result.commands == null and result.info != null and result.revealMatch != null and result.searchBounds != null and result.clearSearch != null and result.isLoading != null)
    Swag.assert(result.isLoading!(result.view!))
    Swag.assert(Utf8.contains(result.details.toString(), "HTML"))
    let view = cast(*HtmlViewer) result.view!
    finishHtmlViewer(&host, &result)

    var zoomIn = KeyEvent{kind: .Pressed, key: .OemPlus, modifiers: .Control}
    Swag.assert(view.hookOnChildEvent!(view.view, &zoomIn))
    Swag.assert(view.zoomPercent == 125 and view.view.documentStyle.bodyFontSize == 20)
    var resetZoom = KeyEvent{kind: .Pressed, key: .D0, modifiers: .Control}
    Swag.assert(view.hookOnChildEvent!(view.view, &resetZoom) and view.zoomPercent == 100)

    let source = expect File.readAllText(fileName.toString())
    let offset = source.indexOf("immutable")
    Swag.assert(offset != Swag.U64.Max)
    let match = Viewer.SearchMatch{offset: offset, length: "immutable".count}
    Swag.assert(result.revealMatch!(result.view!, match, "immutable"))
    var bounds: Math.Rectangle
    Swag.assert(result.searchBounds!(result.view!, match, &bounds) and !bounds.isEmpty())
    result.clearSearch!(result.view!)
}

// The rendered document and its host-owned zoom chrome have a dedicated visual contract.
#[Swag.TestTag("golden")]
#test
{
    var host: Testing.HeadlessHost
    host.setup(820, 560)
    defer host.shutdown()
    host.theme.setSwagDark()
    host.theme.metrics.surfaceWnd_ShadowSize   = 0
    host.theme.metrics.surfaceWnd_CornerRadius = 0
    host.notify(.ThemeChanged)

    let infoBar = Wnd.create'ViewerActionBar(&host.root, {0, 0, 0, 40})
    infoBar.dockStyle       = .Top
    infoBar.backgroundStyle = .InformationBar
    infoBar.padding         = {16, 4, 16, 4}
    var result = openTestViewer(htmlViewerPlugin(), &host.root, htmlViewerFixturePath().toString(), infoParent: infoBar)
    Swag.assert(result.view != null and result.info != null)
    infoBar.centerGroup = result.info
    let view = cast(*HtmlViewer) result.view!
    finishHtmlViewer(&host, &result)
    view.dockStyle       = .Center
    result.info!.dockStyle = .None

    host.root.applyLayout()
    host.settleAnimations(&host.root, 4)
    Testing.assertContentFits(&host.root)
    var image = host.render(&host.root)
    Pixel.Testing.assertImageGolden(&image, "viewer.html.document")
}

// File-open failures cross the viewer boundary instead of becoming viewer-specific content.
#test
{
    var host: Testing.HeadlessHost
    host.setup(640, 360)
    defer host.shutdown()

    let fileName = Path.combine(Env.getSpecialDirectory(.Temp).toString(), Format.toString("missing_scope_html_%.html", Guid64.random()).toString())
    var result   = openTestViewer(htmlViewerPlugin(), &host.root, fileName.toString(), commandParent: &host.root)
    Swag.assert(result.view == null and result.commands == null)
    Swag.assert(!result.failureReason.isEmpty())
}
