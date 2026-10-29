#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core, Pixel

/// Predefined dialogs fit their shared layers around the content instead of keeping stale blank rows.
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

// A prompt is as tall as its help line, not as tall as the shell it opened in.
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

// Fitting a resizable editor preserves the authored editor height and makes it the minimum.
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

// The about box measures its header and message instead of retaining the old 300-unit shell.
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

// The application form supplies the common version, build, source, copyright, and tile.
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

// Renders `dlg` on its own surface, its shadow included, over the ground of the window it stands above.
func renderDialog(host: *Testing.HeadlessHost, dlg: *Dialog)->Image
{
    dlg.applyLayout()
    return host.renderSurface(unwrap dlg.surface)
}

// Pins the composition of every predefined box against the charter pictures, in Encre and in Papier.
#[Swag.TestTag("golden")]
#test
{
    for light in [false, true]
    {
        var host: Testing.HeadlessHost
        host.setup(900, 600)
        if light
        {
            host.theme.setLight()
            host.notify(.ThemeChanged)
        }

        let suffix = light ? "paper" : "ink"

        let question = MessageDlg.create(&host.surface, "Reload viewerchrome.swg? The reading position is kept.", {title: "The file changed on disk."})
        question.addButton("Reload", Dialog.BtnOk, true)
        question.addButton("Ignore", Dialog.BtnCancel)
        question.adaptSizeToMessage()
        var image = renderDialog(&host, &question.dialog)
        Pixel.Testing.assertImageGolden(&image, Format.toString("dialogs.message.%", suffix).toString())

        let failure = MessageDlg.create(&host.surface, "The file is damaged.", {title: "Cannot open this file.", failure: true, detail: "Error code: 0x80070017"})
        failure.addButton(strings().dlg_Close, Dialog.BtnOk, true)
        failure.adaptSizeToMessage()
        image = renderDialog(&host, &failure.dialog)
        Pixel.Testing.assertImageGolden(&image, Format.toString("dialogs.error.%", suffix).toString())

        let prompt = EditDlg.createSingleLine(&host.surface, {title: "Go to Address", message: "Decimal, or hexadecimal preceded by 0x.", text: "0x0001F400", confirmButtonText: "Go"})
        image = renderDialog(&host, &prompt.dialog)
        Pixel.Testing.assertImageGolden(&image, Format.toString("dialogs.prompt.%", suffix).toString())

        let form = FormDlg.create(&host.surface, {title: "Change Password", confirmButtonText: "Apply"})
        discard form.form.addPasswordField("Current password")
        discard form.form.addPasswordField("New password")
        discard form.form.addPasswordField("Confirm", placeholder: "Type the new password again", help: "Leave empty to remove only the password.")
        form.form.computeLayout()
        form.adaptSizeToForm()
        image = renderDialog(&host, &form.dialog)
        Pixel.Testing.assertImageGolden(&image, Format.toString("dialogs.form.%", suffix).toString())

        let about = AboutDlg.create(&host.surface, {
            surfaceTitle: "Swag Scope",
            contentTitle: "Swag Scope",
            message: "Code, text, Markdown, HTML, PDF, images, video, sound, MIDI, fonts, tables, subtitles, archives.\n\nCreated with <url>Swag</url> · <url>Source</url>\nCopyright © 2026 Christophe Beaudet",
            surfaceIcon: {},
            contentIcon: host.theme.icon(.About, host.theme.metrics.dialog_TileSize),
            identity: "0.1.1173 · 28 October 2026"})
        image = renderDialog(&host, &about.dialog)
        Pixel.Testing.assertImageGolden(&image, Format.toString("dialogs.about.%", suffix).toString())
    }
}

// Returns `count` bytes of text, for a file of a known size.
func filler(count: u64)->String
{
    var result: String
    for count do
        result += 'x'u8
    return result
}

// Pins the file box against the charter picture: places as text tabs, the path written before the
// filter, quiet rows with faint dates and sizes, and the type filter in the bottom-left slot.
#[Swag.TestTag("golden")]
#test
{
    let root   = Path.combine(Env.getSpecialDirectory(.Temp).toString(), "swag-filedlg-golden")
    let folder = Path.combine(root.toString(), "swag")
    discard catch Directory.delete(root.toString(), recurse: true)
    expect Directory.create(Path.combine(folder.toString(), "design").toString(), recurse: true)
    defer discard catch Directory.delete(root.toString(), recurse: true)
    discard expect File.writeAllText(Path.combine(folder.toString(), "AGENTS.md").toString(), filler(4200).toString())
    discard expect File.writeAllText(Path.combine(folder.toString(), "CLAUDE.md").toString(), "@AGENTS.md")
    discard expect File.writeAllText(Path.combine(folder.toString(), "README.md").toString(), filler(8100).toString())
    discard expect File.writeAllText(Path.combine(folder.toString(), "build.swgs").toString(), "#run")

    for light in [false, true]
    {
        var host: Testing.HeadlessHost
        host.setup(900, 640)
        if light
        {
            host.theme.setLight()
            host.notify(.ThemeChanged)
        }

        var opt: FileDlgOptions
        opt.mode          = .SelectFile
        opt.showDrives    = false
        opt.initialFolder = folder.toString()
        opt.shortcuts.add({type: Env.SpecialDirectory.Temp, name: "Documents"})
        let dlg = FileDlg.create(&host.surface, opt)
        dlg.browser.pathField.setText(".md")

        // The disk dates the files of today; the picture keeps one moment.
        for line, idx in dlg.browser.listCtrl.lines do
            discard line!.setItem(1, Format.toString("10-2% 21:30", 6 - idx).toString())
        dlg.browser.listCtrl.selectLine(0)

        let image = renderDialog(&host, &dlg.dialog)
        Pixel.Testing.assertImageGolden(&image, Format.toString("dialogs.file.%", light ? "paper" : "ink").toString())
        dlg.surface!.destroy()
        host.pump()
    }
}

// Pins the other modes of the file box: choosing a folder names it, a save keeps its rows as
// context under the name, and choosing several files counts them.
#[Swag.TestTag("golden")]
#test
{
    let root   = Path.combine(Env.getSpecialDirectory(.Temp).toString(), "swag-filedlg-modes")
    let folder = Path.combine(root.toString(), "swag")
    discard catch Directory.delete(root.toString(), recurse: true)
    expect Directory.create(Path.combine(folder.toString(), "design").toString(), recurse: true)
    expect Directory.create(Path.combine(folder.toString(), "tools").toString(), recurse: true)
    defer discard catch Directory.delete(root.toString(), recurse: true)
    discard expect File.writeAllText(Path.combine(folder.toString(), "AGENTS.md").toString(), filler(4200).toString())
    discard expect File.writeAllText(Path.combine(folder.toString(), "README.md").toString(), filler(8100).toString())
    discard expect File.writeAllText(Path.combine(folder.toString(), "capture-2026-10-27.png").toString(), filler(412000).toString())
    discard expect File.writeAllText(Path.combine(folder.toString(), "maquette.png").toString(), filler(2800000).toString())

    for light in [false, true]
    {
        var host: Testing.HeadlessHost
        host.setup(900, 640)
        if light
        {
            host.theme.setLight()
            host.notify(.ThemeChanged)
        }

        let suffix = light ? "paper" : "ink"
        for mode in [FileDlgMode.SelectFolder, .CreateFile, .SelectFiles]
        {
            var opt: FileDlgOptions
            opt.mode          = mode
            opt.showDrives    = false
            opt.initialFolder = folder.toString()
            opt.shortcuts.add({type: Env.SpecialDirectory.Temp, name: "Documents"})
            if mode == .CreateFile
            {
                opt.initialName = "capture-2026-10-28.png"
                opt.filters.add({name: "PNG Image", extensions: ".png"})
            }

            let dlg = FileDlg.create(&host.surface, opt)
            if mode == .SelectFiles do
                dlg.browser.pathField.setText(".md")

            // The disk dates the files of today; the picture keeps one moment.
            for line, idx in dlg.browser.listCtrl.lines do
                discard line!.setItem(1, Format.toString("10-2% 21:30", 7 - idx).toString())

            var name: string
            switch mode
            {
            case .SelectFolder:
                dlg.browser.listCtrl.selectLine(0)
                name = "folder"
            case .CreateFile:
                name = "save"
            default:
                dlg.browser.listCtrl.selectLine(0)
                dlg.browser.listCtrl.selectLine(1)
                name = "files"
            }

            let image = renderDialog(&host, &dlg.dialog)
            Pixel.Testing.assertImageGolden(&image, Format.toString("dialogs.file.%.%", name, suffix).toString())
            dlg.surface!.destroy()
            host.pump()
        }

        // The two questions a file box asks on the way: the name of a new folder, and whether a
        // save replaces a file.
        let folderBox = FileDlg.createNewFolderBox(&host.surface, "Documents / swag")
        var image     = renderDialog(&host, &folderBox.dlg.dialog)
        Pixel.Testing.assertImageGolden(&image, Format.toString("dialogs.file.newfolder.%", suffix).toString())
        folderBox.dlg.surface!.destroy()
        host.pump()

        let replace = FileDlg.createReplaceBox(&host.surface, "rapport.pdf", "2.4 MB · modified 2026-10-27 11:20")
        image = renderDialog(&host, &replace.dialog)
        Pixel.Testing.assertImageGolden(&image, Format.toString("dialogs.file.replace.%", suffix).toString())
        replace.surface!.destroy()
        host.pump()
    }
}

// A question is as wide as its actions need, and never narrower than the family's floor.
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

// A message box holds the message it was fitted to, whatever that message measures.
//
// The box takes the extent of its own text as its width, and that extent is fractional: the
// window tree is laid out on whole logical units and the window itself is placed on whole
// physical pixels. Committed as measured, the width came back a fraction short, the message
// wrapped one line more than the box had been made tall for, and the box clipped the very text
// it was fitted to. Only some lengths land on a losing fraction, so the case is swept instead
// of picked — a two-sentence error box was one of them.
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

// An oversized message stays inside the available surface height and exposes its final line.
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

// An application block added to the about box grows it, and stops growing it at the measure.
//
// What an application lists there — the formats it opens, the plugins it carries — has no natural
// length, so the box follows it only as far as [[Gui.AboutDlg.MaxSectionsHeight]] and the column
// scrolls from there. A box that followed it further would be as tall as the display.
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
