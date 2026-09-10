#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Pixel, Gui

// A real PNG contributes its metadata to the host side panel, with localized chrome and copyable values.
#[Swag.TestTag("golden")]
#test
{
    let fileName = Testing.tempFilePath("scope-metadata-", ".png")
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
    defer
    {
        discard catch host.app.setLanguage(ReferenceLanguage)
        host.shutdown()
    }

    host.theme.setSwagDark()
    host.notify(.ThemeChanged)
    var session = openTestViewer(imageViewerPlugin(), &host.root, fileName)
    let view    = cast(*ImageViewer) session.view!
    completeViewerBackgroundLoad(&host, &view.load, view.loadTimer)
    view.dockStyle = .Center
    session.commands!.hide()
    session.info!.hide()
    Swag.assert(session.sidePanel != null and session.sidePanelButton != null)
    Swag.assert(not session.sidePanelHost!.isLocallyVisible())
    session.sidePanelButton!.setChecked(true)
    session.sidePanelButton!.sigCheckedChanged.call(session.sidePanelButton!)
    Swag.assert(session.sidePanelHost!.isLocallyVisible())
    Swag.assert(Utf8.contains(view.information.text(), "Author: Camera owner"))
    Swag.assert(view.information.list.lineCount() == view.information.data.rows.count)
    Swag.assert(Utf8.contains(view.information.text(), "96 × 64 px"))
    view.information.copyButton.sigPressed.call(view.information.copyButton)

    host.root.applyLayout()
    host.settleAnimations(&host.root, 4)
    Testing.assertContentFits(&host.root)
    Swag.assert(view.position.width > session.sidePanelHost!.position.width)
    var image = host.render(&host.root)
    Pixel.Testing.assertImageGolden(&image, "viewer.media.information")

    expect host.app.setLanguage("fr")
    host.notify(.LanguageChanged)
    Swag.assert(view.information.title.text() == "Informations")
    Swag.assert(view.information.list.header.itemAt(0).name.raw == "Propriété")
    Swag.assert(Utf8.contains(view.information.text(), "Author: Camera owner"))
    Testing.assertContentFits(&host.root)
    host.clickWnd(view.information.closeButton)
    Swag.assert(not session.sidePanelHost!.isLocallyVisible() and not session.sidePanelButton!.isChecked)
}

// JPEG EXIF is interpreted from the preserved APP1 payload, while decodeMetadata remains optional.
#test
{
    let fileName = Testing.tempFilePath("scope-exif-", ".jpg")
    defer discard catch File.delete(fileName)
    var source = Image.create(8, 8, .RGB8)
    source.fill(Color.fromRgb(255, 255, 255))
    var record: ImageMetadata
    record.signature = 1
    record.tag       = "Exif"
    record.value     = "\0II\x2a\0\x08\0\0\0\x01\0\x0f\x01\x02\0\x06\0\0\0\x1a\0\0\0\0\0\0\0Camera"
    source.metadata.add(record)
    expect source.save(fileName)
    let decoded = expect Image.load(fileName)
    var data: MediaInfoData
    data.addImageMetadata(decoded.metadata.toSlice())
    var found = false
    for row in data.rows where row.name == "Make" and row.value == "Camera" do
        found = true
    Swag.assert(found)

    var file       = expect File.MappedFile.open(fileName)
    let region     = expect file.mapAll()
    let pixelsOnly = expect Image.decode(fileName, region.bytes(), {decodeMetadata: false})
    Swag.assert(pixelsOnly.isValid() and pixelsOnly.metadata.isEmpty())
    source.metadata[0].value = "\0II"
    var malformed: MediaInfoData
    malformed.addImageMetadata(source.metadata.toSlice())
    Swag.assert(malformed.rows.count == 2 and malformed.rows[1].field == .Unavailable)
}
