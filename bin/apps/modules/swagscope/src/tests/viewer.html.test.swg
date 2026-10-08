#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Pixel, Gui, Viewers

func htmlViewerFixturePath()->String => Path.combine(Path.combine(Path.directoryName(#curlocation.fileName)!, "datas"), "viewer.html")

func finishHtmlViewer(host: *Testing.HeadlessHost, result: *ViewerSession)
{
    var attempts: u32
    while result.isLoading!() and attempts < 100
    {
        Threading.Thread.sleep(5'ms)
        host.app.runFrame()
        attempts += 1
    }

    Swag.assert(not result.isLoading!())
}

// The viewer remains a thin ABI adapter around the reusable GUI control.
#test
{
    let fileName = htmlViewerFixturePath()

    var host: Testing.HeadlessHost
    host.setup(640, 360)
    defer
    {
        discard catch host.app.setLanguage(ReferenceLanguage)
        host.shutdown()
    }

    var result = openTestViewer(Html.viewerPlugin(), &host.root, fileName, commandParent: &host.root)
    Swag.assert(result.view != null)
    Swag.assert(result.commands == null and result.info != null and result.revealMatch != null and result.searchBounds != null and result.clearSearch != null and result.isLoading != null)
    Swag.assert(result.isLoading())
    Swag.assert(Utf8.contains(result.details, "HTML"))
    let view = assume cast(*Html.Panel, result.view)
    finishHtmlViewer(&host, &result)
    Swag.assert(result.view != null and result.revealMatch != null and result.searchBounds != null and result.clearSearch != null)

    var zoomIn = KeyEvent{kind: .Pressed, key: .OemPlus, modifiers: .Control}
    Swag.assert(view.hookOnChildEvent!(view.view, &zoomIn))
    Swag.assert(view.zoomPercent == 125 and view.view.documentStyle.bodyFontSize == 20)
    var resetZoom = KeyEvent{kind: .Pressed, key: .D0, modifiers: .Control}
    Swag.assert(view.hookOnChildEvent(view.view, &resetZoom) and view.zoomPercent == 100)

    let source = expect File.readAllText(fileName)
    let offset = source.indexOf("immutable")
    Swag.assert(offset != Swag.U64.Max)
    let match    = Viewer.SearchMatch{offset: offset, length: "immutable".count}
    let revealed = result.revealMatch(match, "immutable")
    Swag.assert(revealed)
    var bounds: Math.Rectangle
    Swag.assert(result.searchBounds(match, &bounds) and not bounds.isEmpty())

    let oldTip = String.from(view.zoomLabel.toolTip)
    expect host.app.setLanguage("fr")
    host.notify(.LanguageChanged)
    Swag.assert(view.zoomLabel.toolTip == Html.texts().ui_ZoomMenu and view.zoomLabel.toolTip != oldTip)
    Swag.assert(view.zoomPercent == 100 and result.searchBounds(match, &bounds))
    expect host.app.setLanguage(ReferenceLanguage)
    host.notify(.LanguageChanged)
    Swag.assert(view.zoomLabel.toolTip == oldTip)
    result.clearSearch()
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

    with let infoBar = Wnd.create'ViewerActionBar(&host.root, {0, 0, 0, 40})
    {
        .dockStyle       = .Top
        .backgroundStyle = .InformationBar
        .padding         = {16, 4, 16, 4}
    }

    var result = openTestViewer(Html.viewerPlugin(), &host.root, htmlViewerFixturePath(), infoParent: infoBar)
    Swag.assert(result.view != null and result.info != null)
    infoBar.centerGroup = result.info
    let view = assume cast(*Html.Panel, result.view)
    assertViewerInfoButton(view.zoomLabel)
    Swag.assert(result.info.preferredSize.x == ViewerZoomSlotWidth)
    finishHtmlViewer(&host, &result)
    Swag.assert(result.info != null)
    view.dockStyle        = .Center
    result.info.dockStyle = .None

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

    let fileName = Gui.Testing.tempFilePath("scope-html-missing-", ".html")
    var result   = openTestViewer(Html.viewerPlugin(), &host.root, fileName, commandParent: &host.root)
    Swag.assert(result.view == null and result.commands == null)
    Swag.assert(not result.failureReason.isEmpty())
}
