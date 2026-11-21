#global if #command == Swag.CompilerCommand.Test and WINDOWS
#global private

// The first-mount choice fits at the window's minimum size in French.
#[Swag.TestTag("golden")]
#test
{
    var host: Testing.HeadlessHost
    let window = testSetupMainWindow(&host, 1.25)
    expect host.app.setLanguage("fr")
    defer expect host.app.setLanguage(ReferenceLanguage)
    host.theme.setDark()
    host.notify(.ThemeChanged)

    var captured: bool
    host.app.sigFrame += func|host = &host, captured = &captured|(_)
    {
        if captured[] do
            return
        for surface in host.app.surfaces
        {
            if surface.view() is MessageDlg as dialog
            {
                captured[] = true
                Testing.assertContentFits(dialog)
                host.keyPress(.Tab)
                host.keyPress(.Tab, .Shift)
                let image = host.renderSurface(surface)
                Pixel.Testing.assertImageGolden(&image, "winfsp.choice.encre")
                dialog.closeWithResult(Dialog.BtnCancel)
                return
            }
        }
    }

    discard window.chooseDriverForMount("/install-driver.vault")
    Swag.require(captured)
}

// The installation link remains visible after the portable choice, at the end of Options.
#[Swag.TestTag("golden")]
#test
{
    var host: Testing.HeadlessHost
    let window = testSetupMainWindow(&host)
    host.theme.setLight()
    host.notify(.ThemeChanged)
    window.preferPortableWinFsp = true
    window.showPage(.Options, animate: false)
    let scroll = window.optionsPage.scroll
    scroll.setScrollPos(0, scroll.scrollSize.y)
    let image = host.renderSettled(&host.surfaceWnd)
    Pixel.Testing.assertImageGolden(&image, "winfsp.options.papier")
}
