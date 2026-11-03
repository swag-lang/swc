#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Pixel, Gui, Viewers

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
    defer discard catch host.app.setLanguage(ReferenceLanguage)

    host.theme.setDark()
    host.notify(.ThemeChanged)
    var session = openTestViewer(Picture.viewerPlugin(), &host.root, fileName)
    let view    = assume cast(*Picture.Panel, session.view)
    completeViewerBackgroundLoad(&host, &view.load)
    view.dockStyle = .Center
    session.commands!.hide()
    session.info!.hide()
    Swag.assert(session.sidePanel != null and session.sidePanelButton != null)
    Swag.assert(not session.sidePanelHost!.isLocallyVisible())
    session.sidePanelButton.setChecked(true)
    session.sidePanelButton.sigCheckedChanged.call(session.sidePanelButton)
    Swag.assert(session.sidePanelHost.isLocallyVisible())
    Swag.assert(Utf8.contains(view.information.text(), "Author: Camera owner"))
    Swag.assert(view.information.list.lineCount() == view.information.data.rows.count)
    Swag.assert(Utf8.contains(view.information.text(), "96 × 64 px"))
    view.information.copyButton.sigPressed.call(view.information.copyButton)

    host.root.applyLayout()
    let originalWidth = session.sidePanelHost.position.width
    session.sidePanelHost.resize(224, session.sidePanelHost.position.height)
    host.root.applyLayout()
    let narrowListWidth = view.information.list.listView.position.width
    Swag.assert(view.information.list.header == null)
    Testing.assertContentFits(view.information)
    session.sidePanelHost.resize(564, session.sidePanelHost.position.height)
    host.root.applyLayout()
    Swag.assert(view.information.list.listView.position.width > narrowListWidth + 100)
    Testing.assertContentFits(view.information)
    session.sidePanelHost.resize(originalWidth, session.sidePanelHost.position.height)
    host.root.applyLayout()
    host.settleAnimations(&host.root, 4)
    Testing.assertContentFits(&host.root)
    Swag.assert(view.position.width > session.sidePanelHost.position.width)
    var image = host.render(&host.root)
    assertScopeImageGolden(&image, "viewer.media.information")

    expect host.app.setLanguage("fr")
    host.notify(.LanguageChanged)
    Swag.assert(view.information.title.text() == "Informations")
    for row, index in view.information.data.rows where row.field == .PixelFormat do
        Swag.assert(Utf8.startsWith(view.information.lines[index].itemAt(0).name.raw, "Format des pixels: "))
    Swag.assert(Utf8.contains(view.information.text(), "Author: Camera owner"))
    Testing.assertContentFits(&host.root)
    host.clickWnd(view.information.closeButton)
    Swag.assert(not session.sidePanelHost.isLocallyVisible() and not session.sidePanelButton.isChecked)
}
