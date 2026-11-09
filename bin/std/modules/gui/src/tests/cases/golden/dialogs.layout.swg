#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core, Pixel

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

        let question = MessageDlg.create(&host.surface, "Reload viewerchrome.swg? The reading position is kept.", {title: "The file changed on disk.", mark: .Question})
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

// The confirmation helper's default answer takes keyboard focus when the modal opens. Keep that
// combined state in the dialog goldens at a scaled display size, where the ring has been clipped.
#[Swag.TestTag("golden")]
#test
{
    let light = false
    var host: Testing.HeadlessHost
    host.setup(600, 400, dpiScale: 1.5)
    if light
    {
        host.theme.setLight()
        host.notify(.ThemeChanged)
    }

    let suffix = light ? "paper" : "ink"
    let dlg    = MessageDlg.create(&host.surface, "The file could not be found.\n\nRemove it from the file history?", {title: "File not found.", mark: .Warning})
    dlg.addButton(strings().dlg_Yes, Dialog.BtnYes)
    let no = dlg.addButton(strings().dlg_No, Dialog.BtnNo, true)
    host.app.setFocusVisible(true)
    no.setFocus()
    dlg.adaptSizeToMessage()

    Swag.require(no.hasVisibleFocus())
    let image = renderDialog(&host, &dlg.dialog)
    Pixel.Testing.assertImageGolden(&image, Format.toString("dialogs.message.focus.%", suffix).toString())
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

    let light = true
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
    let dlg = FileDlg.create(&host.surface, opt)

    // Keep folders and files visible together so their glyphs can be compared.

    pinBrowserDates(dlg.browser)
    dlg.browser.listCtrl.selectLine(0)

    let image = renderDialog(&host, &dlg.dialog)
    Pixel.Testing.assertImageGolden(&image, Format.toString("dialogs.file.%", light ? "paper" : "ink").toString())
    dlg.surface!.destroy()
    host.pump()
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

    let light = true
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

        pinBrowserDates(dlg.browser)

        var name: string
        switch mode
        {
        case .SelectFolder:
            dlg.browser.listCtrl.selectLine(0)
            dlg.browser.choiceLabel.setText("C:/Documents/swag/design")
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
