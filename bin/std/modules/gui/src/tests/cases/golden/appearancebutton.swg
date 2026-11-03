#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core, Pixel

// Pins the shared application glyphs at the two sizes where standard chrome uses them.
#[Swag.TestTag("golden")]
#test
{
    var host: Testing.HeadlessHost
    host.setup(248, 96)

    let icons = [ThemeIcons.Appearance, .OpenFile, .ParentFolder, .History, .OpenExternal]
    for icon, idx in icons
    {
        let x = 8 + cast(f32, idx) * 48
        IconButton.create(&host.root, host.theme.icon(icon, 20), Math.Rectangle{x, 8, 40, 36})
        IconButton.create(&host.root, host.theme.icon(icon, 16), Math.Rectangle{x, 52, 40, 36})
    }

    var image = host.renderSettled(&host.root)
    Pixel.Testing.assertImageGolden(&image, "themeicons.application-actions")
}

// Generic document and media actions come from the same atlas in every application.
#[Swag.TestTag("golden")]
#test
{
    var host: Testing.HeadlessHost
    host.setup(248, 184)

    let icons = [ThemeIcons.FullScreen, .ExitFullScreen, .SeekBackward, .SeekForward, .Volume,
                 ThemeIcons.VolumeMute, .FitView, .ActualSize, .Wrap, .AudioTracks,
                 ThemeIcons.SearchPrevious, .SearchNext, .MatchWholeWord, .PlayOnce, .RepeatOne,
                 ThemeIcons.RepeatAll, .Shuffle, .PlaybackSpeed]
    for icon, idx in icons
    {
        let x = 8 + cast(f32, (idx % 5)) * 48
        let y = 8 + cast(f32, (idx / 5)) * 44
        IconButton.create(&host.root, host.theme.icon(icon, 20), Math.Rectangle{x, y, 40, 36})
    }

    var image = host.renderSettled(&host.root)
    Pixel.Testing.assertImageGolden(&image, "themeicons.document-media-actions")
}

// The standard appearance action occupies the caption slot immediately before native controls
// and applies both kinds of presentation choice before notifying its owner.
#[Swag.TestTag("golden")]
#test
{
    var host: Testing.HeadlessHost
    host.setup(480, 240)
    defer discard catch host.app.setLanguage(ReferenceLanguage)

    host.surface.flags = SurfaceFlags.StandardWindow
    host.surfaceWnd.create(&host.root, null)
    host.surfaceWnd.sendResizeEvent()

    let button = AppearanceButton.create(&host.surface)
    host.surfaceWnd.sendResizeEvent()
    Swag.require(button.parent == &host.surfaceWnd)
    Swag.require(host.surfaceWnd.captionButtons.count == 1)
    Swag.require(button.position.right() < host.surfaceWnd.clientRect().right())

    var themeChanges, languageChanges, aboutRequests: u32
    button.sigThemeChanged += func|count = &themeChanges|(_)
    {
        count[] += 1
    }

    button.sigLanguageChanged += func|count = &languageChanges|(appearance)
    {
        Swag.require(appearance.language == "fr")
        count[] += 1
    }

    button.sigAboutRequested += func|count = &aboutRequests|(_)
    {
        count[] += 1
    }

    let encre  = ThemeColors.encrePalette().ground
    let papier = ThemeColors.papierPalette().ground
    Swag.require(button.appearanceTheme == .Dark)
    button.setAppearanceTheme(.Light, notify: true)
    Swag.require(button.appearanceTheme == .Light and host.theme.colors.ground == papier)
    button.setAppearanceTheme(.Dark, notify: true)
    Swag.require(button.appearanceTheme == .Dark and host.theme.colors.ground == encre)

    // The button opens a sheet whose theme page applies a theme as soon as it is chosen. System
    // follows the setting of the operating system, and keeps following it when it changes.
    host.activateOptionRowWhenShown(strings().appearance_Theme)
    host.thenActivateOptionRow(strings().appearance_System)
    host.clickWnd(button)
    Swag.require(host.autoHandled)
    Swag.require(button.appearanceTheme == .System and host.app.appearance == .System)
    host.app.setSystemPrefersLight(true)
    Swag.require(host.theme.colors.ground == papier)
    host.app.setSystemPrefersLight(false)
    Swag.require(host.theme.colors.ground == encre)
    expect button.setAppearanceLanguage("fr", notify: true)
    Swag.require(themeChanges == 3 and languageChanges == 1)
    Swag.require(host.app.language() == "fr")

    // About closes the sheet before its owner opens anything.
    host.activateOptionRowWhenShown(strings().appearance_About)
    host.clickWnd(button)
    Swag.require(aboutRequests == 1)

    // The first page names the palette and the language in force.
    var options: OptionSheet.Page
    button.describeAppearance(&options)
    Swag.require(options.rows[0].value == strings().appearance_System)
    Swag.require(options.rows[2].kind == .Action and options.rows[2].closesSheet)

    // From the title bar the sheet joins its button and is drawn above the content of the window.
    var sheetChecked: bool
    host.app.sigFrame += func|host = &host, button, checked = &sheetChecked|(_)
    {
        let sheet = host.capturedOptionSheet()
        if checked[] or not sheet do
            return
        host.finishAnimations()
        Swag.require(sheet.parent == &host.surfaceWnd and not sheet.opensUp)
        Swag.require(Math.abs(sheet.localToSurface(Math.Point{0, sheet.body.y}).y - button.surfaceRect().bottom()) < 0.5)
        Swag.require(sheet.activateRow(strings().appearance_Theme))
        host.finishAnimations()
        var image = host.render(&host.surfaceWnd)
        Pixel.Testing.assertImageGolden(&image, "appearancebutton.sheet.caption")
        sheet.close()
        checked[] = true
    }

    host.clickWnd(button)
    host.app.sigFrame.clear()
    Swag.require(sheetChecked)

    let popup = MenuCtrl.createPopup(button)
    let sub   = MenuCtrl.createPopup(popup)
    sub.addItem("Swag", "Gui.Appearance.Test")
    popup.addPopup("Theme", sub)
    Swag.require(popup.parent == &host.surfaceWnd)
    Swag.require(sub.parent == &host.surfaceWnd)

    var popupChecked: bool
    host.app.sigFrame += func|host = &host, button, popup, sub, checked = &popupChecked|(_)
    {
        if checked[] do
            return

        let anchor  = button.surfaceRect()
        let bodyTop = popup.surfaceRect().y + popup.popupBarItemSurfaceRect.height + popup.themeMetrics().menuPopup_ShadowSize
        Swag.require(Math.abs(bodyTop - anchor.bottom()) < 0.5)
        let submenuOpened = host.openPopupSubMenu("Theme")
        Swag.require(submenuOpened)
        Swag.require(sub.surfaceRect().y < host.surfaceWnd.stripHeight())
        var image = host.render(&host.surfaceWnd)
        Pixel.Testing.assertImageGolden(&image, "appearancebutton.popup.caption")
        sub.setEndModal(null)
        checked[] = true
    }

    discard popup.doModal(button, autoDestroy: true)
    Swag.require(popupChecked)

    button.destroy()
    host.pump()
    Swag.require(host.surfaceWnd.captionButtons.isEmpty())
}
