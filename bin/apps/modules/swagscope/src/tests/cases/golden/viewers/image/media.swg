#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Pixel, Gui, Viewers

// A real PNG contributes its metadata to the same application information sheet as every other
// viewer, with the shared caption trigger, close action and translated section labels.
#[Swag.TestTag("golden")]
#test
{
    // The picture stands alone in its folder: a rank among whatever else the temporary folder
    // holds would make the line of readings depend on the machine.
    let folder = Testing.tempFilePath("scope-metadata-", "")
    expect Directory.create(folder, recurse: true)
    let fileName = Path.combine(folder, "scope-metadata.png")
    defer discard catch File.delete(fileName)
    var source = Image.create(96, 64, .RGB8)
    source.fill(Color.fromRgb(45, 70, 96))
    var record: ImageMetadata
    record.tag   = "Author"
    record.value = "Camera owner"
    source.metadata.add(record)
    expect source.save(fileName)

    var host: Testing.HeadlessHost
    host.setup(960, 540)
    defer discard catch host.app.setLanguage(ReferenceLanguage)
    host.theme.setDark()
    host.notify(.ThemeChanged)

    let window = ViewerWindow.create(&host.surfaceWnd, createViewerPluginRegistry())
    window.openFile(fileName, remember: false)
    completeQueuedViewerFile(&host, window)
    let view = assume cast(*Picture.Panel, window.currentView)
    completeViewerBackgroundLoad(&host, &view.load)
    window.toggleInformation()
    window.infoSheet.setTitle("scope-metadata.png")
    window.infoSheet.setIdentity("fixtures / images")
    window.applyLayout()

    let information = window.infoSheet.text()
    Swag.require(Utf8.contains(information, "Author\nCamera owner"))
    Swag.require(Utf8.contains(information, "96 × 64 px"))
    Swag.require(window.informationCaptionButton.isLocallyVisible())
    host.settleAnimations(window)
    var image = host.render(&host.surfaceWnd)
    assertScopeImageGolden(&image, "viewer.media.information")

    expect host.app.setLanguage("fr")
    host.notify(.LanguageChanged)
    window.refreshInformation()
    Swag.require(Utf8.contains(window.infoSheet.text(), "Format des pixels"))
    Swag.require(Utf8.contains(window.infoSheet.text(), "Author\nCamera owner"))
}
