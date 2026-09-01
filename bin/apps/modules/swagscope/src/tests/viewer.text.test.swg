#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Pixel, Gui

func textViewerFixturePath()->String
{
    return Path.combine(Path.combine(Path.directoryName(#curlocation.fileName)!, "datas"), "comprehensive.txt")
}

func finishTextStatistics(host: *Testing.HeadlessHost, view: *TextView)
{
    while !Atomic.get(&view.statisticsState) do
        host.pump()
    if view.statisticsTimer do
        host.fireTimer(view.statisticsTimer)
}

// The viewer-owned controls route their documented shortcuts, update the document, and follow a
// live language change.  Statistics are only shown for the encoding that computed them.
#test
{
    var host: Testing.HeadlessHost
    host.setup(800, 520)
    defer
    {
        discard catch host.app.setLanguage(ReferenceLanguage)
        host.shutdown()
    }

    let fileName = textViewerFixturePath()
    var result   = openTestViewer(textViewerPlugin(), &host.root, fileName.toString(), commandParent: &host.root, infoParent: &host.root)
    Swag.assert(result.view != null and result.commands != null and result.info != null)
    Swag.assert(result.revealMatch != null and result.searchBounds != null and result.clearSearch != null and result.isLoading != null and result.retire != null)

    let view = cast(*TextView) result.view!
    assertViewerInfoButton(view.zoomLabel)
    Swag.assert(result.info!.preferredSize.x == ViewerZoomSlotWidth)
    finishTextStatistics(&host, view)
    let lineDetails = Format.toString(textStrings().ui_Lines, view.statistics.lines)
    Swag.assert(Utf8.contains(view.detailsText().toSlice(), lineDetails.toSlice()))

    var toggleWrap = KeyEvent{kind: .Pressed, key: .W, modifiers: .Control}
    Swag.assert(view.hookOnChildEvent!(view.editor, &toggleWrap) and !view.wrapping)
    var zoomIn = KeyEvent{kind: .Pressed, key: .OemPlus, modifiers: .Control}
    Swag.assert(view.hookOnChildEvent!(view.editor, &zoomIn) and view.zoomPercent == 125)
    var resetZoom = KeyEvent{kind: .Pressed, key: .D0, modifiers: .Control}
    Swag.assert(view.hookOnChildEvent!(view.editor, &resetZoom) and view.zoomPercent == 100)

    view.applyEncoding(.Utf16Le)
    let changedDetails = view.detailsText()
    Swag.assert(changedDetails == Format.toString(textStrings().ui_Details, "UTF-16 LE"))

    let oldEncodingTip = String.from(view.encodingCombo.toolTip)
    expect host.app.setLanguage("fr")
    host.notify(.LanguageChanged)
    Swag.assert(view.wrapButton.toolTip == textStrings().ui_WrapOff)
    Swag.assert(view.encodingCombo.toolTip == textStrings().ui_Encoding and view.encodingCombo.toolTip != oldEncodingTip)
    Swag.assert(view.zoomLabel.toolTip == textStrings().ui_ZoomMenu)
}

// Basic text owns a focused visual contract just like every format-specific document surface.
#[Swag.TestTag("golden")]
#test
{
    var host: Testing.HeadlessHost
    host.setup(820, 540)
    defer host.shutdown()
    host.theme.setSwagDark()
    host.theme.metrics.surfaceWnd_ShadowSize   = 0
    host.theme.metrics.surfaceWnd_CornerRadius = 0
    host.notify(.ThemeChanged)

    let commandBar = Wnd.create'ViewerActionBar(&host.root, {0, 0, 0, 52})
    commandBar.dockStyle       = .Bottom
    commandBar.backgroundStyle = .Window
    commandBar.padding         = {16, 8, 16, 8}
    let infoBar = Wnd.create'ViewerActionBar(&host.root, {0, 0, 0, 40})
    infoBar.dockStyle       = .Top
    infoBar.backgroundStyle = .InformationBar
    infoBar.padding         = {16, 4, 16, 4}

    var result = openTestViewer(textViewerPlugin(), &host.root, textViewerFixturePath().toString(), commandParent: commandBar, infoParent: infoBar)
    Swag.assert(result.view != null and result.commands != null and result.info != null)
    commandBar.centerGroup = result.commands
    infoBar.centerGroup    = result.info
    let view = cast(*TextView) result.view!
    finishTextStatistics(&host, view)
    view.dockStyle          = .Center
    view.commands.dockStyle = .None
    view.info.dockStyle     = .None

    host.root.applyLayout()
    host.settleAnimations(&host.root, 4)
    Testing.assertContentFits(&host.root)
    var image = host.render(&host.root)
    Pixel.Testing.assertImageGolden(&image, "viewer.text.document")
}
