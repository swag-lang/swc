#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Pixel, Gui.Print

// A French printer dialog fits the paper and placement choices on Papier at 125 percent.
#[Swag.TestTag("golden")]
#test
{
    var host: Testing.HeadlessHost
    host.setup(960, 760, 1.25)
    host.theme.setLight()
    host.notify(.ThemeChanged)
    expect host.app.setLanguage("fr")
    defer expect host.app.setLanguage(ReferenceLanguage)

    var captured = false
    host.app.sigFrame += func|host = &host, &captured|(app)
    {
        if captured or app.modalSurfaces.isEmpty() do
            return

        let surface = app.modalSurfaces.back()
        if surface.view() is Dialog as dlg
        {
            Swag.require(dlg.title.text == strings().print_Title)
            captured = true

            // The headless modal has no monitor to supply its native scale.
            let size  = surface.size()
            let scale = host.surface.dpiScale
            surface.setDpiScaleRaw(scale)
            var position = surface.position
            position.width  = Math.ceil(size.x * scale)
            position.height = Math.ceil(size.y * scale)
            surface.setPosition(position)
            surface.center(&host.surface)
            dlg.applyLayout()
            var image = host.renderSurface(surface)
            Pixel.Testing.assertImageGolden(&image, "dialogs.print.settings.paper")
            Swag.require(host.clickModalButton(Dialog.BtnCancel))
        }
    }

    var document: Document
    document.name  = "Capture"
    document.image = Image.create(120, 80, .RGB8)
    let printers: [1] Printer = [{name: "Imprimante du bureau", id: "office", isDefault: true}]
    PrintDlg.showDocument(&host.surface, &document, "", printers)
    Swag.require(captured)
}

// A text document with several pages shows the sheet, page navigation and range on Encre.
#[Swag.TestTag("golden")]
#test
{
    var host: Testing.HeadlessHost
    host.setup(960, 760)
    host.theme.setDark()
    host.notify(.ThemeChanged)
    expect host.app.setLanguage(ReferenceLanguage)

    var confirmedSettings = false
    var captured = false
    var returned = false
    host.app.sigFrame += func|host = &host, &confirmedSettings, &captured, &returned|(app)
    {
        if returned or app.modalSurfaces.isEmpty() do
            return

        let surface = app.modalSurfaces.back()
        if surface.view() is Dialog as dlg
        {
            if not confirmedSettings and dlg.title.text == strings().print_Title
            {
                confirmedSettings = true
                Swag.require(host.clickModalButton(PrintDlg.PreviewButton))
            }
            elif not captured and dlg.title.text == strings().print_Preview
            {
                captured = true
                var image = host.renderSurface(surface)
                Pixel.Testing.assertImageGolden(&image, "dialogs.print.preview.ink")

                let previous = unwrap dlg.childById("gui.print.preview.previous")
                let next     = unwrap dlg.childById("gui.print.preview.next")
                let count    = assume cast(*Label, unwrap dlg.childById("gui.print.preview.count"))
                Swag.require(previous.isDisabled() and next.isEnabled() and count.text() == "Page 1 of 2")
                host.clickWnd(next)
                Swag.require(previous.isEnabled() and next.isDisabled() and count.text() == "Page 2 of 2")
                let navigation = unwrap next.parent
                navigation.setFocus()
                host.keyPress(.Home)
                Swag.require(previous.isDisabled() and next.isEnabled() and count.text() == "Page 1 of 2")
                let range = unwrap host.findEditByLabel(dlg, strings().print_Range)
                range.setText("2")
                host.clickWnd(unwrap dlg.leadingControl)
            }
            elif captured and dlg.title.text == strings().print_Title
            {
                returned = true
                let range = unwrap host.findEditByLabel(dlg, strings().print_Range)
                Swag.require(range.text() == "2")
                Swag.require(host.clickModalButton(Dialog.BtnCancel))
            }
        }
    }

    var document: Document
    document.kind = .Text
    document.name = "Observation log"
    document.text = "OBSERVATION LOG\n\n"
    for i in 62 do
        document.text.appendFormat("Entry %{D02}    Sample collected and recorded.\n", i + 1)
    let printers: Array'Printer
    PrintDlg.showDocument(&host.surface, &document, "", printers.toSlice())
    Swag.require(confirmedSettings and captured and returned)
}

// Submission keeps the activity track and its cancel action together on Papier.
#[Swag.TestTag("golden")]
#test
{
    var host: Testing.HeadlessHost
    host.setup(900, 600)
    host.theme.setLight()
    host.notify(.ThemeChanged)

    let dlg = PrintDlg.createWorkDialog(&host.surface, strings().print_Sending)
    let bar = assume cast(*ProgressBar, (unwrap dlg.contentView).children[0])
    bar.animationPhase = 0.5
    var image = host.renderSurface(unwrap dlg.surface)
    Pixel.Testing.assertImageGolden(&image, "dialogs.print.progress.paper")
}
