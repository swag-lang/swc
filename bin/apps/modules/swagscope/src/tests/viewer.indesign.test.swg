#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Pixel, Gui

// The fixed 4 KiB master-page unit is the file-level contract this fixture records.
private const IndesignFixtureHeaderSize = 4096'u64

// Returns the minimal dual-header document fixture shared by this viewer and the smoke run.
private func indesignFixturePath()->String
{
    return Path.combine(Path.combine(Path.directoryName(#curlocation.fileName)!, "datas"), "viewer.indd")
}

#test
{
    let document = expect loadIndesignDocument(indesignFixturePath().toString())
    Swag.assert(document.header.offset == IndesignFixtureHeaderSize)
    Swag.assert(!document.header.bigEndian and document.header.formatVersion == 7)
    Swag.assert(document.header.sequence == 2)
    Swag.assert(document.declaredBytes == document.fileSize and document.declaredBytes == cast(u64) document.header.storagePages * IndesignFixtureHeaderSize)
    Swag.assert(document.previews.count == 2)
    Swag.assert(document.previews[0].page == 1 and document.previews[0].payloadStart < document.previews[0].payloadEnd)
    Swag.assert(document.previews[1].page == 2 and document.previews[1].payloadStart < document.previews[1].payloadEnd)
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
