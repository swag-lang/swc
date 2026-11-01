#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Pixel, Gui, Viewers

func archiveViewerFixturePath()->String => scopeTestDataPath("viewer.archive.zip")

// Offscreen archive rendering retains the embedded viewer for thumbnail generation. Interactive
// navigation uses Explorer instead; its tests cover the common folder and ZIP surface.
#[Swag.TestTag("golden")]
#test
{
    let archiveFile = archiveViewerFixturePath()

    var host: Testing.HeadlessHost
    host.setup(1180, 720)
    shipFrame(&host)

    var index = createViewerPluginRegistry()

    with let window = ViewerWindow.create(&host.surfaceWnd, #move index)
    {
        .thumbnailMode = true
        .resize(1180, 720)
        .openFile(archiveFile)
    }

    completeViewerWindowClassification(&host, window)

    let viewer = assume cast(*Archive.Panel, window.currentView)
    completeViewerBackgroundLoad(&host, &viewer.load)
    Swag.assert(viewer.list.lineCount() == 4)
    Swag.assert(viewer.entryLines.count == 2)

    // Shell icon pixels depend on Windows, file associations, and its scaling path. Keep
    // checking that the viewer supplied icons, then render fixed folder/JSON/text inputs.
    let iconFile  = scopeTestDataPath("viewer.archive.icons.png")
    let iconImage = expect Image.load(iconFile)
    var icons     = ImageList.create(host.app.renderer.addImage(&iconImage), 16, 16)
    defer icons.release(host.app.renderer)
    Swag.assert(icons.frameCount == 3)
    for index in viewer.list.lineCount()
    {
        let row  = unwrap viewer.list.lineAt(index)
        let item = row.itemAt(0)
        Swag.assert(item.icon.isValid())
        let frame = row.canExpand() ? 0 : item.name == "sample.json" ? 1 : 2
        item.icon = Icon.from(&icons, frame)
    }

    let line         = unwrap viewer.entryLines[1]
    var visibleIndex = Swag.U32.Max
    for index in viewer.list.lineCount() where viewer.list.lineAt(index) == line do
        visibleIndex = index
    Swag.assert(visibleIndex != Swag.U32.Max)
    viewer.list.selectLine(visibleIndex)
    viewer.requestPreview(1)
    Swag.assert(viewer.pendingPreview == Swag.U64.Max)

    viewer.extract.task.wait()
    host.pump()
    Swag.assert(not viewer.previewFile.isEmpty())

    let embedded = assume cast(*EmbeddedViewer, viewer.previewPane.children[0])
    Swag.assert(embedded.choices[0].key == "text")
    Swag.assert(embedded.currentView != null)

    let textView = assume cast(*PlainText.Panel, embedded.currentView)
    completeTextReads(&host, textView)
    host.fireTimer(textView.loadTimer)

    Swag.assert(not viewer.embedded.isLoading())
    host.settleAnimations(window, 4)
    var image = host.render(window)
    Pixel.Testing.assertImageGolden(&image, "viewer.archive.document")

    var matches: Array'Viewer.SearchMatch
    let session = &window.instances[window.activeChoiceIndex]
    collectViewerMatches(unwrap session.collectMatches, "readme", &matches)
    Swag.assert(matches.count == 1 and matches[0].major == 1)
    let revealed = session.revealMatch!(matches[0], "readme")
    Swag.assert(revealed)
    var bounds: Math.Rectangle
    Swag.assert(session.searchBounds!(matches[0], &bounds) and not bounds.isEmpty())
    session.clearSearch!()

    defer discard catch host.app.setLanguage(ReferenceLanguage)
    expect host.app.setLanguage("fr")
    host.notify(.LanguageChanged)
    Swag.assert(viewer.list.header.itemAt(0).name.raw == Archive.texts().ui_ColName)
    Swag.assert(viewer.list.header.itemAt(1).name.raw == Archive.texts().ui_ColSize)
    expect host.app.setLanguage(ReferenceLanguage)
    host.notify(.LanguageChanged)
}
