#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Pixel, Gui

// The fixed 4 KiB master-page unit is the file-level contract this fixture records.
private const IndesignFixtureHeaderSize = 4096'u64
private const LinkedIdmlInteractiveBudgetMs = 1_000'u64

// Returns the minimal dual-header document fixture shared by this viewer and the smoke run.
private func indesignFixturePath()->String
{
    return Path.combine(Path.combine(Path.directoryName(#curlocation.fileName)!, "datas"), "viewer.indd")
}

// An external, licensed IDML package exercises positioned content rather than a saved bitmap.
private func idmlFixturePath()->String
{
    return Path.combine(Path.combine(Path.directoryName(#curlocation.fileName)!, "datas"), "uni-halle-52a.idml")
}

// This published native document exercises the binary header and its independently saved preview.
private func nativeFixturePath()->String
{
    return Path.combine(Path.combine(Path.directoryName(#curlocation.fileName)!, "datas"), "publicdomain.indd")
}

private func linkedIdmlFixturePath()->String
{
    return Path.combine(Path.combine(Path.directoryName(#curlocation.fileName)!, "datas"), "iosdc-2025-indesign-template.idml")
}

#test
{
    let image = "<Image ImageTypeName=\"$ID/PNG\"><Contents><![CDATA[QUJD]]></Contents></Image>"
    Swag.assert(idmlEmbeddedGraphicDataUri(image) == "data:image/png;base64,QUJD")
    Swag.assert(idmlEmbeddedGraphicDataUri("<Image ImageTypeName=\"$ID/EPS\"><Contents><![CDATA[QUJD]]></Contents></Image>").isEmpty())
    Swag.assert(idmlEmbeddedGraphicDataUri("<Image ImageTypeName=\"$ID/PNG\"><MetadataPacketPreference><Contents><![CDATA[<?xpacket begin=\"\"?>]]></Contents></MetadataPacketPreference></Image>").isEmpty())
}

#test
{
    let document = expect loadIndesignDocument(indesignFixturePath().toString())
    Swag.assert(document.header.offset == IndesignFixtureHeaderSize)
    Swag.assert(!document.header.bigEndian and document.header.formatVersion == 7)
    Swag.assert(document.header.sequence == 2)
    Swag.assert(document.declaredBytes == document.fileSize and document.declaredBytes == cast(u64) document.header.storagePages * IndesignFixtureHeaderSize)
    Swag.assert(document.xmpObjectStreams == 0)
    Swag.assert(document.previews.count == 2)
    Swag.assert(document.previews[0].page == 1 and document.previews[0].payloadStart < document.previews[0].payloadEnd)
    Swag.assert(document.previews[1].page == 2 and document.previews[1].payloadStart < document.previews[1].payloadEnd)
}

// The scene comes from IDML geometry, stories, and swatches. It is not a preview image decoded
// from the package, and this fixture was authored outside the repository.
#test
{
    let document = expect loadIdmlDocument(idmlFixturePath().toString())
    Swag.assert(document.pages.count >= 1)
    Swag.assert(document.pages[0].bounds.width > 400 and document.pages[0].bounds.height > 500)
    Swag.assert(document.pages[0].textFrameCount >= 19)
    Swag.assert(document.pages[0].items.count >= document.pages[0].textFrameCount)
    Swag.assert(Utf8.contains(document.pages[0].html(1).toString(), "idml-page"))
    var tintedItems: u64
    var arrowLines: u64
    for item in document.pages[0].items where item.fill == "rgb(51, 51, 51)" do
        tintedItems += 1
    for item in document.pages[0].items where item.line
    {
        Swag.assert(Utf8.startsWith(item.clipPath.toString(), "clip-path:polygon("))
        if item.lineStartArrow or item.lineEndArrow do
            arrowLines += 1
    }
    Swag.assert(tintedItems >= 42)
    Swag.assert(arrowLines >= 1)
}

// This MIT-licensed editorial source has absolute links saved by InDesign. The bundled title
// graphic exercises the same-folder recovery that keeps a moved document renderable offline.
#test
{
    let document = expect loadIdmlDocument(linkedIdmlFixturePath().toString())
    Swag.assert(document.pages.count >= 2)
    var linkedImages: u64
    var flowedArticleFrames: u64
    var flowedArticleBytes: u64
    var roundedFrames: u64
    var multiColumnFrames: u64
    var missingLinkedImages: u64
    for page in document.pages
    {
        for item in page.items where item.imageFrame
        {
            let imageName = Path.fileName(item.image.toString())
            if imageName == "title.png" or imageName == "qrcode.png"
            {
                linkedImages += 1
                Swag.assert(item.imageHasBounds and item.imageBounds.width > 0 and item.imageBounds.height > 0)
            }
        }
        for item in page.items where item.story == "u113" and item.text.count
        {
            flowedArticleFrames += 1
            flowedArticleBytes += item.text.count
        }
        for item in page.items where item.cornerTopLeft > 0 or item.cornerTopRight > 0 or item.cornerBottomRight > 0 or item.cornerBottomLeft > 0 do
            roundedFrames += 1
        for item in page.items where item.textColumns > 1 do
            multiColumnFrames += 1
        missingLinkedImages += page.missingImageCount()
    }
    Swag.assert(linkedImages == 2)
    Swag.assert(flowedArticleFrames == 4)
    Swag.assert(flowedArticleBytes > 4_000 and flowedArticleBytes < 80_000)
    Swag.assert(roundedFrames >= 4)
    Swag.assert(multiColumnFrames >= 2)
    Swag.assert(missingLinkedImages >= 1)
    var rendered: String
    for page in document.pages do
        rendered += page.html(1)
    Swag.assert(Utf8.contains(rendered.toString(), "font-family:cjk"))
    Swag.assert(Utf8.contains(rendered.toString(), "font-weight:bold;"))
    Swag.assert(Utf8.contains(rendered.toString(), "line-height:"))
    Swag.assert(Utf8.contains(rendered.toString(), "padding-left:"))
    Swag.assert(Utf8.contains(rendered.toString(), "border-radius:"))
    Swag.assert(Utf8.contains(rendered.toString(), "idml-text-column"))
}

// Opening an external editorial source must reach its first usable page promptly, then retain the
// resolved local image sources through navigation and painting.
#[Swag.TestTag("linked")]
#test
{
    var host: Testing.HeadlessHost
    host.setup(800, 520)
    defer host.shutdown()

    var opening: Time.Stopwatch
    opening.start()
    var result = openTestViewer(indesignViewerPlugin(), &host.root, linkedIdmlFixturePath().toString(), commandParent: &host.root)
    let viewer = cast(*IndesignViewer) result.view!
    completeViewerBackgroundLoad(&host, &viewer.load, viewer.loadTimer)
    opening.stop()
    Swag.assert(viewer.isMarkup() and viewer.htmlView != null)
    Swag.assert(opening.elapsedMilliseconds() < LinkedIdmlInteractiveBudgetMs)
    Swag.assert(!viewer.goToTypedPage("0") and !viewer.goToTypedPage("5") and !viewer.goToTypedPage("page 1"))
    Swag.assert(viewer.goToTypedPage("2") and viewer.previewIndex == 1)
    Swag.assert(viewer.goToTypedPage("1") and viewer.previewIndex == 0)
    viewer.setMarkupZoom(125)
    Swag.assert(viewer.zoomLabel.text() == "125 %")
    viewer.fitMarkupWidth()
    Swag.assert(viewer.markupFit and viewer.markupFitWidth and viewer.zoomLabel.text() == indesignStrings().ui_FitWidth)
    viewer.fitMarkupPage()
    Swag.assert(viewer.markupFit and !viewer.markupFitWidth and viewer.zoomLabel.text() == indesignStrings().ui_Fit)
    var qrcodePage = Swag.U64.Max
    for page, index in viewer.markupPages
    {
        for item in page.items where Path.fileName(item.image.toString()) == "qrcode.png" do
            qrcodePage = index
    }
    Swag.assert(qrcodePage != Swag.U64.Max)
    var pageRender: Time.Stopwatch
    pageRender.start()
    viewer.selectMarkupPage(qrcodePage)
    host.root.applyLayout()
    host.settleAnimations(&host.root, 4)
    pageRender.stop()
    Testing.assertContentFits(viewer)
    let image = host.render(&host.root)
    Swag.assert(image.isValid())
    Swag.assert(pageRender.elapsedMilliseconds() < LinkedIdmlInteractiveBudgetMs)
}

// The linked editorial source must remain a painted document surface, including its two supplied
// PNG assets, rather than degrading into a metadata or image-decoder-only view.
#[Swag.TestTag("golden")]
#test
{
    var host: Testing.HeadlessHost
    host.setup(800, 520)
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
    infoBar.dockStyle       = .Bottom
    infoBar.backgroundStyle = .InformationBar
    infoBar.padding         = {16, 4, 16, 4}

    var result = openTestViewer(indesignViewerPlugin(), &host.root, linkedIdmlFixturePath().toString(), commandParent: commandBar, infoParent: infoBar)
    commandBar.centerGroup = result.commands
    infoBar.centerGroup    = result.info
    let viewer = cast(*IndesignViewer) result.view!
    completeViewerBackgroundLoad(&host, &viewer.load, viewer.loadTimer)
    viewer.dockStyle          = .Center
    viewer.commands.dockStyle = .None
    viewer.info.dockStyle     = .None
    host.root.applyLayout()
    host.settleAnimations(&host.root, 4)
    Testing.assertContentFits(viewer)
    var firstPage = host.render(&host.root)
    Pixel.Testing.assertImageGolden(&firstPage, "viewer.indesign.idml.linked.page1")

    viewer.fitMarkupWidth()
    host.root.applyLayout()
    host.settleAnimations(&host.root, 4)
    Testing.assertContentFits(viewer)
    var fitWidth = host.render(&host.root)
    Pixel.Testing.assertImageGolden(&fitWidth, "viewer.indesign.idml.linked.fitwidth")
    viewer.fitMarkupPage()

    var qrcodePage = Swag.U64.Max
    for page, index in viewer.markupPages
    {
        for item in page.items where Path.fileName(item.image.toString()) == "qrcode.png" do
            qrcodePage = index
    }
    Swag.assert(qrcodePage != Swag.U64.Max)
    viewer.selectMarkupPage(qrcodePage)
    host.root.applyLayout()
    host.settleAnimations(&host.root, 4)
    Testing.assertContentFits(viewer)
    var qrcode = host.render(&host.root)
    Pixel.Testing.assertImageGolden(&qrcode, "viewer.indesign.idml.linked.qrcode")
}

// A real native document validates the binary header path separately from the synthetic fixture.
#test
{
    let document = expect loadIndesignDocument(nativeFixturePath().toString())
    Swag.assert(document.fileSize > 2 * 1024 * 1024)
    Swag.assert(document.header.storagePages > 0)
    Swag.assert(document.xmpObjectStreams == 1)
    Swag.assert(!document.previews.isEmpty())
}

// The external IDML document reaches the visible surface as positioned, selectable page content.
#[Swag.TestTag("golden")]
#test
{
    var host: Testing.HeadlessHost
    host.setup(800, 520)
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
    infoBar.dockStyle       = .Bottom
    infoBar.backgroundStyle = .InformationBar
    infoBar.padding         = {16, 4, 16, 4}

    var result = openTestViewer(indesignViewerPlugin(), &host.root, idmlFixturePath().toString(), commandParent: commandBar, infoParent: infoBar)
    Swag.assert(result.view != null and result.commands != null and result.info != null)
    commandBar.centerGroup = result.commands
    infoBar.centerGroup    = result.info

    let viewer = cast(*IndesignViewer) result.view!
    completeViewerBackgroundLoad(&host, &viewer.load, viewer.loadTimer)
    Swag.assert(viewer.isMarkup() and viewer.htmlView != null and !viewer.imageView.isVisible())
    Swag.assert(viewer.zoomLabel.isVisible() and viewer.zoomLabel.text() == indesignStrings().ui_Fit)
    Swag.assert(Utf8.contains(viewer.details.toString(), "InDesign Markup page") and Utf8.contains(viewer.details.toString(), "missing images"))
    Swag.assert(viewer.pageLabel.toolTip == "Choose page")
    var matches: Array'Viewer.SearchMatch
    viewer.collectMatches("Schriftwerke", {}, &matches)
    Swag.assert(!matches.isEmpty())
    Swag.assert(viewer.revealMatch(matches[0], "Schriftwerke"))
    var searchBounds: Math.Rectangle
    Swag.assert(viewer.searchBounds(&searchBounds))
    viewer.clearSearch()
    viewer.htmlView!.selectAll()
    Swag.assert(viewer.htmlView!.hasSelection() and Utf8.contains(viewer.htmlView!.selectedText().toString(), "Schriftwerke"))
    viewer.htmlView!.clearSelection()
    viewer.htmlView!.setFocus()
    host.keyPress(.Home)
    viewer.dockStyle          = .Center
    viewer.commands.dockStyle = .None
    viewer.info.dockStyle     = .None

    host.root.applyLayout()
    host.settleAnimations(&host.root, 4)
    Testing.assertContentFits(viewer)
    var image = host.render(&host.root)
    Pixel.Testing.assertImageGolden(&image, "viewer.indesign.idml.document")

    if viewer.pageCount() > 1
    {
        host.clickWnd(viewer.nextButton)
        Swag.assert(viewer.previewIndex == 1)
        viewer.htmlView!.setFocus()
        host.keyPress(.Home)
        Swag.assert(viewer.previewIndex == 0)
    }
}

// Pins the saved InDesign page pixels as the viewer's primary surface, rather than presenting the
// native header as a substitute for the document itself.
#[Swag.TestTag("golden")]
#test
{
    let fileName = indesignFixturePath()

    var host: Testing.HeadlessHost
    host.setup(800, 520)
    defer host.shutdown()
    defer discard catch host.app.setLanguage(ReferenceLanguage)
    host.theme.setSwagDark()
    host.notify(.ThemeChanged)

    let commandBar = Wnd.create'ViewerActionBar(&host.root, {0, 0, 0, 52})
    commandBar.dockStyle       = .Bottom
    commandBar.backgroundStyle = .Window
    commandBar.padding         = {16, 8, 16, 8}
    let infoBar = Wnd.create'ViewerActionBar(&host.root, {0, 0, 0, 40})
    infoBar.dockStyle       = .Bottom
    infoBar.backgroundStyle = .InformationBar
    infoBar.padding         = {16, 4, 16, 4}

    var result = openTestViewer(indesignViewerPlugin(), &host.root, fileName, commandParent: commandBar, infoParent: infoBar)
    Swag.assert(result.view != null and result.commands != null and result.info != null)
    commandBar.centerGroup = result.commands
    infoBar.centerGroup    = result.info

    let viewer = cast(*IndesignViewer) result.view!
    completeViewerBackgroundLoad(&host, &viewer.load, viewer.loadTimer)
    completeViewerBackgroundLoad(&host, &viewer.previewLoad, viewer.previewLoadTimer)
    viewer.dockStyle          = .Center
    viewer.commands.dockStyle = .None
    viewer.info.dockStyle     = .None
    assertViewerInfoButton(viewer.zoomLabel)
    Swag.assert(viewer.zoomLabel.text() != "")
    Swag.assert(viewer.details == "InDesign · page 1 of 2 · saved preview 320 × 460")
    Swag.assert(viewer.pageLabel.text() == "Page 1 / 2")
    Swag.assert(!viewer.previousButton.isEnabled() and viewer.nextButton.isEnabled())
    Swag.assert(viewer.pageLabel.toolTip == "Choose saved preview")
    Swag.assert(viewer.imageView.isFitted and viewer.imageView.effectiveZoom() > 0)
    viewer.imageView.setZoom(1.25)
    Swag.assert(viewer.zoomLabel.text() == "125 %")
    viewer.imageView.setFocus()
    host.keyPress(.F)
    Swag.assert(viewer.imageView.isFitted)

    host.root.applyLayout()
    host.settleAnimations(&host.root, 4)
    Testing.assertContentFits(viewer)
    var image = host.render(&host.root)
    Pixel.Testing.assertImageGolden(&image, "viewer.indesign.document.page1")

    host.clickWnd(viewer.nextButton)
    completeViewerBackgroundLoad(&host, &viewer.previewLoad, viewer.previewLoadTimer)
    Swag.assert(viewer.previewIndex == 1 and viewer.details == "InDesign · page 2 of 2 · saved preview 460 × 320")
    Swag.assert(viewer.pageLabel.text() == "Page 2 / 2")
    Swag.assert(viewer.previousButton.isEnabled() and !viewer.nextButton.isEnabled())
    host.root.applyLayout()
    host.settleAnimations(&host.root, 4)
    Testing.assertContentFits(viewer)
    var secondPage = host.render(&host.root)
    Pixel.Testing.assertImageGolden(&secondPage, "viewer.indesign.document.page2")

    host.clickWnd(viewer.previousButton)
    Swag.assert(viewer.previewIndex == 0 and viewer.pageLabel.text() == "Page 1 / 2")
    host.clickPopupMenuItemWhenShown("scope.indesign.page.1")
    viewer.pageLabel.sigPressed.call(viewer.pageLabel)
    host.pump()
    Swag.assert(viewer.previewIndex == 1 and viewer.pageLabel.text() == "Page 2 / 2")
    viewer.imageView.setFocus()
    host.keyPress(.Home)
    Swag.assert(viewer.previewIndex == 0 and viewer.pageLabel.text() == "Page 1 / 2")

    expect host.app.setLanguage("fr")
    host.notify(.LanguageChanged)
    host.root.applyLayout()
    Swag.assert(viewer.details == "InDesign · page 1 sur 2 · aperçu enregistré 320 × 460")
    Swag.assert(viewer.previousButton.toolTip == "Aperçu enregistré précédent" and viewer.nextButton.toolTip == "Aperçu enregistré suivant")
    Testing.assertContentFits(viewer)
}

#test
{
    let fileName = Gui.Testing.tempFilePath("scope-indesign-bad-", ".indd")
    defer discard catch File.delete(fileName)
    expect File.writeAllBytes(fileName, "not an InDesign document")

    var host: Testing.HeadlessHost
    host.setup(640, 360)
    defer host.shutdown()
    var result = openTestViewer(indesignViewerPlugin(), &host.root, fileName, commandParent: &host.root)
    Swag.assert(result.view != null and result.commands != null)
    let viewer = cast(*IndesignViewer) result.view!
    completeViewerBackgroundLoad(&host, &viewer.load, viewer.loadTimer)
    Swag.assert(!viewer.failureReason.isEmpty())
}
