#global if #command == Swag.CompilerCommand.Test
#global private
using Swag, Core, Pixel

#test
{
    var host: Testing.HeadlessHost
    host.setup(900, 600)

    let dlg     = EditDlg.createSingleLine(&host.surface, {title: "Rename", message: "Enter the new name."})
    let metrics = dlg.themeMetrics()

    Swag.assert(dlg.surface!.flags.has(.Sheet))
    Swag.assert(Math.abs(dlg.label.margin.y - metrics.dialog_BtnPadding * 2) < 0.5)
    let contentHeight = dlg.edit!.position.height + dlg.label.position.height + dlg.label.margin.y
    var expected      = contentHeight + dlg.padding.y + metrics.dialog_Padding
    expected += dlg.buttonBar.position.height + dlg.buttonBar.margin.y + 2 * metrics.wnd_BorderSize + 2 * dlg.surface.shadowMargin()
    Swag.assert(Math.abs(dlg.surface.position.height - Math.ceil(expected) * dlg.surface.dpiScale) < 1.5)
}
#test
{
    var host: Testing.HeadlessHost
    host.setup(900, 600)

    var options: EditDlgOptions
    options.title   = "Rename"
    options.message = "Enter the new name."
    let short = EditDlg.createSingleLine(&host.surface, options)

    options.message = "Enter the new name. It has to be unique inside this folder, and it keeps the extension the file already carries, so a name typed without one is completed."
    let long = EditDlg.createSingleLine(&host.surface, options)

    Swag.assert(long.surface!.position.height > short.surface!.position.height)
    Swag.assert(long.label.itf.measureContent(Math.Point{long.label.position.width, 0}).y <= long.label.position.height + 0.5)

    short.surface.destroy()
    long.surface.destroy()
    host.pump()
}
#test
{
    var host: Testing.HeadlessHost
    host.setup(900, 600)

    let options = EditDlgOptions{title: "Description", editorHeight: 150}
    let dlg     = EditDlg.createMultiLine(&host.surface, options)

    Swag.assert(dlg.label.name.raw == strings().dlg_MultiLineHint)
    Swag.assert(dlg.label.position.y >= dlg.richEdit!.position.bottom())
    let contentHeight = dlg.richEdit.position.height + dlg.label.position.height + dlg.label.margin.y
    let outerHeight   = contentHeight + dlg.chromeHeight()
    Swag.assert(Math.abs(dlg.richEdit.position.height - cast(f32, options.editorHeight)) < 0.5)
    Swag.assert(Math.abs(dlg.surface!.position.height - Math.ceil(outerHeight) * dlg.surface.dpiScale) < 1.5)
    Swag.assert(Math.abs(dlg.surface.minSize.y - dlg.surface.position.height / dlg.surface.dpiScale) < 0.5)
}
#test
{
    var host: Testing.HeadlessHost
    host.setup(900, 600)

    let params = AboutDlgParams{
        surfaceTitle: "About",
        contentTitle: "Swag",
        message: "A systems programming language.",
        surfaceIcon: Icon{},
        contentIcon: Icon{},
        identity: "1.2.3 · 23 August 2026"}
    let dlg = AboutDlg.create(&host.surface, params)

    let metrics       = dlg.themeMetrics()
    var contentHeight = dlg.identityView.position.height
    contentHeight += dlg.labelMessage.measure(Math.Point{dlg.labelMessage.position.width, 0}).preferred.y
    contentHeight += metrics.dialog_BtnPadding * 2
    Swag.assert(Math.abs(dlg.surface!.position.height - Math.ceil(contentHeight + dlg.chromeHeight()) * dlg.surface.dpiScale) < 1.5)

    // No band frames the identity, and the box has no title line: the name names it.
    Swag.assert(dlg.identityView.backgroundStyle == .Transparent)
    Swag.assert(dlg.title.raw.isEmpty())
    Swag.assert(dlg.identityView.isAncestorOf(dlg.labelMessageTitle))
    Swag.assert(dlg.identityView.isAncestorOf(dlg.labelIdentity))
    Swag.assert(dlg.labelIdentity.position.y >= dlg.labelMessageTitle.position.bottom())
    Swag.assert(dlg.identityView.position.bottom() <= dlg.labelMessage.position.y)
}
#test
{
    var host: Testing.HeadlessHost
    host.setup(900, 600)

    let icon = Image.create(32, 32, .RGBA8)
    host.app.setAppIcon(icon)
    let dlg = AboutDlg.createApplication(&host.surface, {
        productName: "sTestBench",
        version: "1.2.3",
        buildDate: {year: 2026, month: 8, day: 23},
        sourceUrl: "https://example.com/source",
        copyrightHolder: "Test Holder"})

    Swag.assert(dlg.surface!.wnd.name.raw == "sTestBench")
    Swag.assert(dlg.labelMessageTitle.text() == "sTestBench")
    Swag.assert(Utf8.startsWith(dlg.labelIdentity.text(), "1.2.3"))
    Swag.assert(Utf8.contains(dlg.labelMessage.text(), "Test Holder"))
    Swag.assert(dlg.labelIcon.icon.isValid())
    Swag.assert(dlg.labelIcon.icon.sizeY == dlg.themeMetrics().dialog_TileSize)
    Swag.assert(dlg.identityView.isAncestorOf(dlg.labelIcon))
}
#test
{
    var host: Testing.HeadlessHost
    host.setup(900, 600)

    // Short actions: the box opens at the floor instead of closing in on three small buttons
    // until the bar is the whole box.
    let small = MessageDlg.create(&host.surface, "Save changes?")
    small.addButton("Yes", Dialog.BtnYes)
    small.addButton("No", Dialog.BtnNo)
    small.addButton("Cancel", Dialog.BtnCancel, true)
    small.adaptSizeToMessage()
    Swag.assert(Math.abs(small.surface!.size().x - (MessageDlg.MinMessageWidth + 2 * small.surface.shadowMargin())) < 1)

    // Long actions: the bar decides, and no invisible button is reserved beside them.
    let wide = MessageDlg.create(&host.surface, "Save changes?")
    wide.addButton("Save the document", Dialog.BtnYes)
    wide.addButton("Discard the changes", Dialog.BtnNo)
    wide.addButton("Keep editing", Dialog.BtnCancel, true)
    wide.adaptSizeToMessage()

    let metrics  = wide.themeMetrics()
    var expected = 2 * metrics.dialog_Padding + 2 * metrics.wnd_BorderSize
    for btn in wide.buttons do
        expected += btn.position.width
    expected += cast(f32, (wide.buttons.count - 1)) * metrics.dialog_BtnPadding
    Swag.assert(expected > MessageDlg.MinMessageWidth)
    Swag.assert(Math.abs(wide.surface!.size().x - (expected + 2 * wide.surface.shadowMargin())) < 1)

    small.surface.destroy()
    wide.surface.destroy()
    host.pump()
}
#test
{
    var host: Testing.HeadlessHost
    host.setup(900, 600, 1.5)

    // One glyph more each round, which walks the fractional part of the measured width across
    // the whole range a rounding can lose.
    var tail: String
    while tail.length < 12
    {
        var message = String.from("Unable to mount the virtual disk.\n\nThe password is incorrect or the container is damaged")
        message += tail
        message += "."

        let dlg = MessageDlg.create(&host.surface, message.toString())
        dlg.addButton("Ok", Dialog.BtnOk, true)

        // A headless surface has no monitor to take a scale from, so the dialog would measure at
        // one and never meet the rounding a scaled display makes it face.
        dlg.surface!.setDpiScaleRaw(1.5)
        dlg.adaptSizeToMessage()

        let needed = dlg.label.itf.measureContent(Math.Point{dlg.label.position.width, 0}).y
        Swag.assert(needed <= dlg.label.position.height + 0.5)

        dlg.surface.destroy()
        host.pump()
        tail += "!"
    }
}
#test
{
    var host: Testing.HeadlessHost
    host.setup(900, 900)

    var message: String
    for index in 80 do
        message += Format.toString("Line % remains readable.\n", index)
    let dlg = MessageDlg.create(&host.surface, message.toString())
    dlg.addButton("Close", Dialog.BtnCancel, true)
    dlg.adaptSizeToMessage(400)
    Swag.assert(dlg.surface!.size().y <= 400)
    Swag.assert(dlg.messageScroll != null)
    let scroll = dlg.messageScroll
    let needed = dlg.label.itf.measureContent(Math.Point{dlg.label.position.width, 0}).y
    Swag.assert(dlg.label.position.height >= needed)
    Swag.assert(scroll.scrollSize.y > scroll.view.position.height)
    scroll.setFocus()
    host.keyPress(.End)
    Swag.assert(scroll.scrollPosition().y > 0)
    Swag.assert(Math.abs(dlg.label.surfaceRect().bottom() - scroll.view.surfaceRect().bottom()) <= 1)
    host.keyPress(.Home)
    Swag.assert(scroll.scrollPosition().y == 0)
    dlg.surface.destroy()
    host.pump()
}
#test
{
    var host: Testing.HeadlessHost
    host.setup(900, 900)

    let icon = Image.create(32, 32, .RGBA8)
    host.app.setAppIcon(icon)
    let dlg = AboutDlg.createApplication(&host.surface, {
        productName: "sTestBench",
        version: "1.2.3",
        buildDate: {year: 2026, month: 8, day: 23},
        sourceUrl: "https://example.com/source",
        copyrightHolder: "Test Holder"})

    let plainHeight = dlg.surface!.position.height
    Swag.assert(dlg.sectionsScroll == null)

    dlg.addSection("Formats", "One short line of supporting detail.")
    Swag.assert(dlg.sectionsScroll != null)
    let oneHeight = dlg.surface.position.height
    Swag.assert(oneHeight > plainHeight)
    Swag.assert(dlg.sectionsScroll.position.height < AboutDlg.MaxSectionsHeight)

    // A list long enough to have no end of its own.
    var long: String
    for 400 do
        long += "extension, "
    dlg.addSection("Everything", long.toString())

    let scroll = dlg.sectionsScroll
    Swag.assert(scroll.position.height <= AboutDlg.MaxSectionsHeight)
    Swag.assert(scroll.scrollSize.y > scroll.position.height)
    Swag.assert(dlg.surface.position.height > oneHeight)
}
