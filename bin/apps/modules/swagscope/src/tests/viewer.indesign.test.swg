#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Pixel, Gui, Viewers

// A preview worker keeps its failure message until the viewer publishes the completed result.
#test
{
    let source   = indesignFixturePath()
    let document = expect InDesign.loadDocument(source)
    var bytes    = expect File.readAllBytes(source)
    let preview  = &document.previews[0]
    for index in preview.payloadStart until preview.payloadEnd do
        bytes[index] = cast(u8, '!')

    let path = Testing.tempFilePath("scope-indesign-failure-", ".indd")
    defer discard catch File.delete(path)
    discard expect File.writeAllBytes(path, bytes.toSlice())

    var host: Testing.HeadlessHost
    host.setup(640, 360)
    defer host.shutdown()
    var result = openTestViewer(InDesign.viewerPlugin(), &host.root, path, commandParent: &host.root)
    Swag.assert(result.view != null)
    let viewer = assume cast(*InDesign.Panel, result.view)
    completeViewerBackgroundLoad(&host, &viewer.load)
    completeViewerBackgroundLoad(&host, &viewer.previewLoad)
    Swag.assert(viewer.failureReason == InDesign.texts().err_Preview)
    Swag.assert(not viewer.hasPreviewContent)
}

// A file URI is checked after percent decoding, before any linked-image probe can run.
#test
{
    Swag.assert(InDesign.Idml.fileUriPath("file:///images/title%20page.png") == "/images/title page.png")
    Swag.assert(InDesign.Idml.fileUriPath("file://localhost/images/title.png") == "/images/title.png")
    Swag.assert(InDesign.Idml.fileUriPath("file://server/share/image.png").isEmpty())
    Swag.assert(InDesign.Idml.fileUriPath("file:////server/share/image.png").isEmpty())
    Swag.assert(InDesign.Idml.fileUriPath("file:%2F%2Fserver/share/image.png").isEmpty())
    Swag.assert(InDesign.Idml.fileUriPath("file:///images/bad%00.png").isEmpty())
    Swag.assert(InDesign.Idml.fileUriPath("file:///images/bad%2.png").isEmpty())
    if WINDOWS
    {
        Swag.assert(InDesign.Idml.fileUriPath("file:%5C%5Cserver/share/image.png").isEmpty())
        Swag.assert(InDesign.Idml.fileUriPath("file:%2F%5Cserver/share/image.png").isEmpty())
        Swag.assert(InDesign.Idml.fileUriPath("file:%5C%5C%3F%5CUNC%5Cserver%5Cshare%5Cimage.png").isEmpty())
        Swag.assert(InDesign.Idml.fileUriPath("file:///C:/images/title%20page.png") == "C:/images/title page.png")
    }
}

// The fixed 4 KiB master-page unit is the file-level contract this fixture records.
const IndesignFixtureHeaderSize = 4096'u64

func indesignDataPath(name: string)->String => Path.combine(Path.combine(Path.directoryName(#curlocation.fileName)!, "datas"), name)

// Returns the minimal dual-header document fixture shared by this viewer and the smoke run.
func indesignFixturePath()->String => indesignDataPath("viewer.indd")

// An external, licensed IDML package exercises positioned content rather than a saved bitmap.
func idmlFixturePath()->String => indesignDataPath("uni-halle-52a.idml")

// This published native document exercises the binary header and its independently saved preview.
func nativeFixturePath()->String => indesignDataPath("publicdomain.indd")

// This MIT-licensed editorial template keeps the absolute image links InDesign saved.
func linkedIdmlFixturePath()->String => indesignDataPath("iosdc-2025-indesign-template.idml")

#test
{
    let image = "<Image ImageTypeName=\"$ID/PNG\"><Contents><![CDATA[QUJD]]></Contents></Image>"
    Swag.assert(InDesign.Idml.embeddedGraphicDataUri(image) == "data:image/png;base64,QUJD")
    Swag.assert(InDesign.Idml.embeddedGraphicDataUri("<Image ImageTypeName=\"$ID/EPS\"><Contents><![CDATA[QUJD]]></Contents></Image>").isEmpty())
    Swag.assert(InDesign.Idml.embeddedGraphicDataUri("<Image ImageTypeName=\"$ID/PNG\"><MetadataPacketPreference><Contents><![CDATA[<?xpacket begin=\"\"?>]]></Contents></MetadataPacketPreference></Image>").isEmpty())
}

#test
{
    let document = expect InDesign.loadDocument(indesignFixturePath())
    Swag.assert(document.header.offset == IndesignFixtureHeaderSize)
    Swag.assert(not document.header.bigEndian and document.header.formatVersion == 7)
    Swag.assert(document.header.sequence == 2)
    Swag.assert(document.declaredBytes == document.fileSize and document.declaredBytes == cast(u64, document.header.storagePages) * IndesignFixtureHeaderSize)
    Swag.assert(document.xmpObjectStreams == 0)
    Swag.assert(document.previews.count == 2)
    Swag.assert(document.previews[0].page == 1 and document.previews[0].payloadStart < document.previews[0].payloadEnd)
    Swag.assert(document.previews[1].page == 2 and document.previews[1].payloadStart < document.previews[1].payloadEnd)
}

// The scene comes from IDML geometry, stories, and swatches. It is not a preview image decoded
// from the package, and this fixture was authored outside the repository.
#test
{
    let document = expect InDesign.Idml.load(idmlFixturePath())
    Swag.assert(document.pages.count >= 1)
    Swag.assert(document.pages[0].bounds.width > 400 and document.pages[0].bounds.height > 500)
    Swag.assert(document.pages[0].textFrameCount >= 19)
    Swag.assert(document.pages[0].items.count >= document.pages[0].textFrameCount)
    Swag.assert(Utf8.contains(document.pages[0].html(1), "idml-page"))
    var tintedItems: u64
    var arrowLines:  u64
    for item in document.pages[0].items where item.fill == "rgb(51, 51, 51)" do
        tintedItems += 1
    for item in document.pages[0].items where item.line
    {
        Swag.assert(Utf8.startsWith(item.clipPath, "clip-path:polygon("))
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
    let document = expect InDesign.Idml.load(linkedIdmlFixturePath())
    Swag.assert(document.pages.count >= 2)
    var linkedImages:        u64
    var flowedArticleFrames: u64
    var flowedArticleBytes:  u64
    var roundedFrames:       u64
    var multiColumnFrames:   u64
    var missingLinkedImages: u64
    for page in document.pages
    {
        for item in page.items where item.imageFrame
        {
            let imageName = Path.fileName(item.image)
            if imageName == "title.png" or imageName == "qrcode.png"
            {
                linkedImages += 1
                Swag.assert(item.imageHasBounds and item.imageBounds.width > 0 and item.imageBounds.height > 0)
            }
        }

        for item in page.items where item.story == "u113" and not item.text.isEmpty()
        {
            flowedArticleFrames += 1
            flowedArticleBytes  += item.text.count
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
    Swag.assert(Utf8.contains(rendered, "font-family:cjk"))
    Swag.assert(Utf8.contains(rendered, "font-weight:bold;"))
    Swag.assert(Utf8.contains(rendered, "line-height:"))
    Swag.assert(Utf8.contains(rendered, "padding-left:"))
    Swag.assert(Utf8.contains(rendered, "border-radius:"))
    Swag.assert(Utf8.contains(rendered, "idml-text-column"))
}

// Opening an external editorial source decodes only the first page's images. Navigation loads
// the selected page's resources, and painting reuses that page's decoded images.
#[Swag.TestTag("linked")]
#test
{
    var host: Testing.HeadlessHost
    host.setup(800, 520)
    defer host.shutdown()

    var result = openTestViewer(InDesign.viewerPlugin(), &host.root, linkedIdmlFixturePath(), commandParent: &host.root)
    let viewer = assume cast(*InDesign.Panel, result.view)
    completeViewerBackgroundLoad(&host, &viewer.load)
    Swag.assert(viewer.isMarkup() and viewer.htmlView != null)
    let firstPageImages = Testing.htmlImageSources(viewer.htmlView)
    Swag.assert(viewer.previewIndex == 0 and firstPageImages.count == 1)
    Swag.assert(Path.fileName(firstPageImages[0]) == "title.png")
    Swag.assert(not viewer.goToTypedPage("0") and not viewer.goToTypedPage("5") and not viewer.goToTypedPage("page 1"))
    Swag.assert(viewer.goToTypedPage("2") and viewer.previewIndex == 1)
    Swag.assert(viewer.goToTypedPage("1") and viewer.previewIndex == 0)
    viewer.setMarkupZoom(125)
    Swag.assert(viewer.zoomLabel.text() == "125 %")
    viewer.fitMarkupWidth()
    Swag.assert(viewer.markupFit and viewer.markupFitWidth and viewer.zoomLabel.text() == InDesign.texts().ui_FitWidth)
    viewer.fitMarkupPage()
    Swag.assert(viewer.markupFit and not viewer.markupFitWidth and viewer.zoomLabel.text() == InDesign.texts().ui_Fit)
    var qrcodePage = Swag.U64.Max
    for page, index in viewer.markupPages
    {
        for item in page.items where Path.fileName(item.image) == "qrcode.png" do
            qrcodePage = index
    }

    Swag.assert(qrcodePage != Swag.U64.Max)
    viewer.selectMarkupPage(qrcodePage)
    let selectedPageImages = Testing.htmlImageSources(viewer.htmlView)
    Swag.assert(selectedPageImages.count == 1)
    Swag.assert(Path.fileName(selectedPageImages[0]) == "qrcode.png")
    host.root.applyLayout()
    host.settleAnimations(&host.root, 4)
    Testing.assertContentFits(viewer)
    let image = host.render(&host.root)
    Swag.assert(image.isValid())
    let paintedImages = Testing.htmlImageSources(viewer.htmlView)
    Swag.assert(paintedImages.count == selectedPageImages.count)
    for index in paintedImages.count do
        Swag.assert(paintedImages[index] == selectedPageImages[index])
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

    with let commandBar = Wnd.create'ViewerActionBar(&host.root, {0, 0, 0, 52})
    {
        .dockStyle       = .Bottom
        .backgroundStyle = .Window
        .padding         = {16, 8, 16, 8}
    }

    with let infoBar = Wnd.create'ViewerActionBar(&host.root, {0, 0, 0, 40})
    {
        .dockStyle       = .Bottom
        .backgroundStyle = .InformationBar
        .padding         = {16, 4, 16, 4}
    }

    var result = openTestViewer(InDesign.viewerPlugin(), &host.root, linkedIdmlFixturePath(), commandParent: commandBar, infoParent: infoBar)
    commandBar.centerGroup = result.commands
    infoBar.centerGroup    = result.info
    let viewer = assume cast(*InDesign.Panel, result.view)
    completeViewerBackgroundLoad(&host, &viewer.load)
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
        for item in page.items where Path.fileName(item.image) == "qrcode.png" do
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
    let document = expect InDesign.loadDocument(nativeFixturePath())
    Swag.assert(document.fileSize > 2 * 1024 * 1024)
    Swag.assert(document.header.storagePages > 0)
    Swag.assert(document.xmpObjectStreams == 1)
    Swag.assert(not document.previews.isEmpty())
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

    with let commandBar = Wnd.create'ViewerActionBar(&host.root, {0, 0, 0, 52})
    {
        .dockStyle       = .Bottom
        .backgroundStyle = .Window
        .padding         = {16, 8, 16, 8}
    }

    with let infoBar = Wnd.create'ViewerActionBar(&host.root, {0, 0, 0, 40})
    {
        .dockStyle       = .Bottom
        .backgroundStyle = .InformationBar
        .padding         = {16, 4, 16, 4}
    }

    var result = openTestViewer(InDesign.viewerPlugin(), &host.root, idmlFixturePath(), commandParent: commandBar, infoParent: infoBar)
    Swag.assert(result.view != null and result.commands != null and result.info != null)
    commandBar.centerGroup = result.commands
    infoBar.centerGroup    = result.info

    let viewer = assume cast(*InDesign.Panel, result.view)
    completeViewerBackgroundLoad(&host, &viewer.load)
    Swag.assert(viewer.isMarkup() and viewer.htmlView != null and not viewer.imageView.isVisible())
    Swag.assert(viewer.zoomLabel.isVisible() and viewer.zoomLabel.text() == InDesign.texts().ui_Fit)
    Swag.assert(Utf8.contains(viewer.details, "InDesign Markup page") and Utf8.contains(viewer.details, "missing images"))
    Swag.assert(viewer.pageLabel.toolTip == "Choose page")
    var matches: Array'Viewer.SearchMatch
    viewer.collectMatches("Schriftwerke", {}, &matches)
    Swag.assert(not matches.isEmpty())
    let revealed = viewer.revealMatch(matches[0], "Schriftwerke")
    Swag.assert(revealed)
    var searchBounds: Math.Rectangle
    Swag.assert(viewer.searchBounds(&searchBounds))
    viewer.clearSearch()
    viewer.htmlView.selectAll()
    Swag.assert(viewer.htmlView.hasSelection() and Utf8.contains(viewer.htmlView.selectedText(), "Schriftwerke"))
    viewer.htmlView.clearSelection()
    viewer.htmlView.setFocus()
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
        viewer.htmlView.setFocus()
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

    with let commandBar = Wnd.create'ViewerActionBar(&host.root, {0, 0, 0, 52})
    {
        .dockStyle       = .Bottom
        .backgroundStyle = .Window
        .padding         = {16, 8, 16, 8}
    }

    with let infoBar = Wnd.create'ViewerActionBar(&host.root, {0, 0, 0, 40})
    {
        .dockStyle       = .Bottom
        .backgroundStyle = .InformationBar
        .padding         = {16, 4, 16, 4}
    }

    var result = openTestViewer(InDesign.viewerPlugin(), &host.root, fileName, commandParent: commandBar, infoParent: infoBar)
    Swag.assert(result.view != null and result.commands != null and result.info != null)
    commandBar.centerGroup = result.commands
    infoBar.centerGroup    = result.info

    let viewer = assume cast(*InDesign.Panel, result.view)
    completeViewerBackgroundLoad(&host, &viewer.load)
    completeViewerBackgroundLoad(&host, &viewer.previewLoad)
    viewer.dockStyle          = .Center
    viewer.commands.dockStyle = .None
    viewer.info.dockStyle     = .None
    assertViewerInfoButton(viewer.zoomLabel)
    Swag.assert(viewer.zoomLabel.text() != "")
    Swag.assert(viewer.details == "InDesign · page 1 of 2 · saved preview 320 × 460")
    Swag.assert(viewer.pageLabel.text() == "Page 1 / 2")
    Swag.assert(not viewer.previousButton.isEnabled() and viewer.nextButton.isEnabled())
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
    completeViewerBackgroundLoad(&host, &viewer.previewLoad)
    Swag.assert(viewer.previewIndex == 1 and viewer.details == "InDesign · page 2 of 2 · saved preview 460 × 320")
    Swag.assert(viewer.pageLabel.text() == "Page 2 / 2")
    Swag.assert(viewer.previousButton.isEnabled() and not viewer.nextButton.isEnabled())
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
    var result = openTestViewer(InDesign.viewerPlugin(), &host.root, fileName, commandParent: &host.root)
    Swag.assert(result.view != null and result.commands != null)
    let viewer = assume cast(*InDesign.Panel, result.view)
    completeViewerBackgroundLoad(&host, &viewer.load)
    Swag.assert(not viewer.failureReason.isEmpty())
}

const IdmlMimeType = "application/vnd.adobe.indesign-idml-package"

// Returns a text frame whose path spans `left, top` to `right, bottom` in spread coordinates.
func idmlTextFrame(self, story, previous, next: string, left, top, right, bottom: s32)->String
{
    const Frame = """<TextFrame Self="%" ParentStory="%" PreviousTextFrame="%" NextTextFrame="%" ItemTransform="1 0 0 1 0 0">
                     <Properties><PathGeometry><GeometryPathType><PathPointArray>
                     <PathPointType Anchor="% %"/><PathPointType Anchor="% %"/><PathPointType Anchor="% %"/><PathPointType Anchor="% %"/>
                     </PathPointArray></GeometryPathType></PathGeometry></Properties></TextFrame>"""
    return Format.toString(Frame, self, story, previous, next, left, top, left, bottom, right, bottom, right, top)
}

// Returns a 100-point square page placed `left` points into its spread.
func idmlPage(self: string, left: s32, master: string = "")->String
{
    return Format.toString("<Page Self=\"%\" Name=\"%\" GeometricBounds=\"0 0 100 100\" ItemTransform=\"1 0 0 1 % 0\" AppliedMaster=\"%\"/>", self, self, left, master)
}

// Writes an IDML package holding `files` after its `mimetype` entry.
func writeIdmlPackage(path: string, files: const [..] StoredZipFile)
{
    var entries: Array'StoredZipFile
    entries.add(StoredZipFile{name: "mimetype", bytes: IdmlMimeType})
    entries.add(files)
    discard expect File.writeAllBytes(path, storedZipBytes(entries.toSlice()).toSlice())
}

// A master text chain copied onto each page flows on that page's copies, and a character range
// that is both underlined and struck through keeps both lines.
#test
{
    var master: String
    master += "<MasterSpread Self=\"m\">"
    master += idmlPage("mp", 0)
    master += idmlTextFrame("ma", "sm", "n", "mb", 10, 10, 90, 40)
    master += idmlTextFrame("mb", "sm", "ma", "n", 10, 50, 90, 90)
    master += "</MasterSpread>"

    var spread: String
    spread += "<Spread Self=\"s\">"
    spread += idmlPage("p1", 0, "m")
    spread += idmlPage("p2", 100, "m")
    spread += idmlTextFrame("t", "st", "n", "n", 20, 20, 80, 80)
    spread += "</Spread>"

    const MasterStory = "<Story Self=\"sm\"><ParagraphStyleRange><CharacterStyleRange><Content>Master one</Content></CharacterStyleRange></ParagraphStyleRange><ParagraphStyleRange><CharacterStyleRange><Content>Master two</Content></CharacterStyleRange></ParagraphStyleRange></Story>"
    const PageStory   = "<Story Self=\"st\"><ParagraphStyleRange><CharacterStyleRange Underline=\"true\" StrikeThru=\"true\"><Content>Both lines</Content></CharacterStyleRange></ParagraphStyleRange></Story>"
    const DesignMap   = "<Document><idPkg:MasterSpread src=\"MasterSpreads/m.xml\"/><idPkg:Spread src=\"Spreads/s.xml\"/></Document>"

    var files: Array'StoredZipFile
    files.add(StoredZipFile{name: "designmap.xml", bytes: DesignMap})
    files.add(StoredZipFile{name: "MasterSpreads/m.xml", bytes: master.toSlice()})
    files.add(StoredZipFile{name: "Spreads/s.xml", bytes: spread.toSlice()})
    files.add(StoredZipFile{name: "Stories/sm.xml", bytes: MasterStory})
    files.add(StoredZipFile{name: "Stories/st.xml", bytes: PageStory})
    let path = Testing.tempFilePath("scope-idml-master-", ".idml")
    defer discard catch File.delete(path)
    writeIdmlPackage(path, files.toSlice())

    let document = expect InDesign.Idml.load(path)
    Swag.assert(document.pages.count == 2)
    for page in document.pages
    {
        var masterFrames: u64
        for item in page.items where item.story == "sm"
        {
            masterFrames += 1
            Swag.assert(Utf8.contains(item.text, item.self == "ma" ? "Master one" : "Master two"))
        }

        Swag.assert(masterFrames == 2)
    }

    var decorated: u64
    for item in document.pages[0].items where item.story == "st"
    {
        decorated += 1
        Swag.assert(Utf8.contains(item.text, "text-decoration:underline line-through;"))
        Swag.assert(not Utf8.contains(item.text, "text-decoration:underline;"))
    }

    Swag.assert(decorated == 1)
}

// The page and frame bounds hold for the whole document, not for each spread.
#test
{
    var spread: String
    spread += "<Spread Self=\"s\">"
    spread += idmlPage("p1", 0)
    spread += idmlPage("p2", 100)
    spread += idmlTextFrame("f1", "", "n", "n", 10, 10, 90, 90)
    spread += idmlTextFrame("f2", "", "n", "n", 110, 10, 190, 90)
    spread += "</Spread>"

    const DesignMap = "<Document><idPkg:Spread src=\"Spreads/s.xml\"/><idPkg:Spread src=\"Spreads/s.xml\"/><idPkg:Spread src=\"Spreads/s.xml\"/></Document>"
    var files: Array'StoredZipFile
    files.add(StoredZipFile{name: "designmap.xml", bytes: DesignMap})
    files.add(StoredZipFile{name: "Spreads/s.xml", bytes: spread.toSlice()})
    let path = Testing.tempFilePath("scope-idml-limits-", ".idml")
    defer discard catch File.delete(path)
    writeIdmlPackage(path, files.toSlice())

    let unbounded = expect InDesign.Idml.load(path)
    var unboundedItems: u64
    for page in unbounded.pages do
        unboundedItems += page.items.count
    Swag.assert(unbounded.pages.count == 6 and unboundedItems == 6)

    let bounded = expect InDesign.Idml.load(path, {pages: 3, frames: 2})
    var boundedItems: u64
    for page in bounded.pages do
        boundedItems += page.items.count
    Swag.assert(bounded.pages.count == 3 and boundedItems == 2)
}

// A relative `file:` link names a picture beside the document, and its path reaches the page
// markup as an escaped attribute value.
#test
{
    let folder = Testing.tempFilePath("scope-idml-a&b-", "")
    expect Directory.create(Path.combine(folder, "images"), recurse: true)
    defer discard catch Directory.delete(folder, recurse: true)
    let picture = expect File.readAllBytes(indesignDataPath("title.png"))
    discard expect File.writeAllBytes(Path.combine(folder, "images/linked.png"), picture.toSlice())

    const Spread = """<Spread Self="s"><Page Self="p" Name="1" GeometricBounds="0 0 100 100" ItemTransform="1 0 0 1 0 0"/>
                      <Rectangle Self="r" ItemTransform="1 0 0 1 0 0"><Properties><PathGeometry><GeometryPathType><PathPointArray>
                      <PathPointType Anchor="10 10"/><PathPointType Anchor="10 90"/><PathPointType Anchor="90 90"/><PathPointType Anchor="90 10"/>
                      </PathPointArray></GeometryPathType></PathGeometry></Properties>
                      <Image Self="i" ItemTransform="1 0 0 1 0 0"><Link Self="l" LinkResourceURI="file:images/linked.png"/></Image></Rectangle></Spread>"""
    const DesignMap = "<Document><idPkg:Spread src=\"Spreads/s.xml\"/></Document>"
    var files: Array'StoredZipFile
    files.add(StoredZipFile{name: "designmap.xml", bytes: DesignMap})
    files.add(StoredZipFile{name: "Spreads/s.xml", bytes: Spread})
    let path = Path.combine(folder, "linked.idml")
    writeIdmlPackage(path, files.toSlice())

    let document = expect InDesign.Idml.load(path)
    Swag.assert(document.pages.count == 1 and document.pages[0].items.count == 1)
    let item = &document.pages[0].items[0]
    Swag.assert(item.imageFrame and Path.fileName(item.image) == "linked.png")
    Swag.assert(Utf8.contains(item.image, "images"))
    let html = document.pages[0].html(1)
    Swag.assert(Utf8.contains(html, "scope-idml-a&amp;b-") and not Utf8.contains(html, "scope-idml-a&b-"))
}
