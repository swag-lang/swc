#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui, Pixel

// The notification menu is a compact detached surface with one drive label and direct commands.
#[Swag.TestTag("golden")]
#test
{
    var host: Testing.HeadlessHost
    let window = testSetupMainWindow(&host)
    fillPictureList(window)

    // Keep this rendering fixture independent of the host-specific privacy label policy.
    window.privacyMode = false
    host.theme.setDark()
    host.notify(.ThemeChanged)
    let panel = unwrap ResidentMenu.open(window)
    panel.stopTimer(&panel.watch)
    var image = host.renderSurface(unwrap panel.surface)
    Pixel.Testing.assertImageGolden(&image, "resident.menu.encre")
    panel.close()
}

// The new resident choices remain reachable at minimum size, in French and Papier.
#[Swag.TestTag("golden")]
#test
{
    var host: Testing.HeadlessHost
    let window = testSetupMainWindow(&host, 1.25)
    defer discard catch g_App.setLanguage(ReferenceLanguage)
    host.theme.setLight()
    expect g_App.setLanguage("fr")
    expect host.app.setLanguage("fr")
    host.notify(.LanguageChanged)
    host.notify(.ThemeChanged)
    window.resident.settings.enabled = true
    window.resident.applySettings()
    window.showPage(.Options, animate: false)
    window.applyLayout()
    window.optionsPage.scroll.setScrollPos(0, window.optionsPage.scroll.scrollSize.y)
    let image = host.renderSettled(&host.surfaceWnd)
    Gui.Testing.assertContentFits(window.optionsPage)
    Pixel.Testing.assertImageGolden(&image, "resident.options.papier")
}

// Force is a separate warning with a safe default and an explicit destructive action.
#[Swag.TestTag("golden")]
#test
{
    var host: Testing.HeadlessHost
    let window = testSetupMainWindow(&host)
    window.resident.showWindow()
    fillPictureList(window)
    defer discard catch g_App.setLanguage(ReferenceLanguage)
    expect g_App.setLanguage("fr")
    expect host.app.setLanguage("fr")
    host.notify(.LanguageChanged)
    host.theme.setLight()
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
                var image = host.renderSurface(surface)
                Pixel.Testing.assertImageGolden(&image, "resident.force.papier")
                dialog.closeWithResult(Dialog.BtnCancel)
                return
            }
        }
    }

    window.forceUnmountVault(window.mountedDrives.drives[0].path)
    Swag.require(captured and window.operation.kind == .None)
    Swag.require(window.mountedDrives.drives.count == 1)
}
