#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Pixel, Gui.Print

// A capture destined for a printer displays placement and copy controls on Papier.
#[Swag.TestTag("golden")]
#test
{
    var host: Testing.HeadlessHost
    host.setup(960, 760)
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
    host.app.sigFrame += func|host = &host, &confirmedSettings, &captured|(app)
    {
        if captured or app.modalSurfaces.isEmpty() do
            return

        let surface = app.modalSurfaces.back()
        if surface.view() is Dialog as dlg
        {
            if not confirmedSettings and dlg.title.text == strings().print_Title
            {
                confirmedSettings = true
                Swag.require(host.clickModalButton(Dialog.BtnOk))
            }
            elif dlg.title.text == strings().print_Preview
            {
                captured = true
                var image = host.renderSurface(surface)
                Pixel.Testing.assertImageGolden(&image, "dialogs.print.preview.ink")
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
    Swag.require(confirmedSettings and captured)
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
