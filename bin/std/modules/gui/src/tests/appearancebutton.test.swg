#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core, Pixel

// Pins the shared application glyphs at the two sizes where standard chrome uses them.
#test
{
    var host: Testing.HeadlessHost
    host.setup(152, 96)
    defer host.shutdown()

    host.theme.setSwagDark()
    host.notify(.ThemeChanged)

    let icons = [ThemeIcons.Appearance, .OpenFile, .ParentFolder, .History]
    for icon, idx in icons
    {
        let x = 8 + cast(f32) idx * 48
        IconButton.create(&host.root, host.theme.icon(icon, 20), {x, 8, 40, 36})
        IconButton.create(&host.root, host.theme.icon(icon, 16), {x, 52, 40, 36})
    }

    host.settleAnimations(&host.root, 4)
    var image = host.render(&host.root)
    Pixel.Testing.assertImageGolden(&image, "themeicons.application-actions")
}

// Generic document and media actions come from the same atlas in every application.
#test
{
    var host: Testing.HeadlessHost
    host.setup(248, 140)
    defer host.shutdown()

    host.theme.setSwagDark()
    host.notify(.ThemeChanged)

    let icons = [ThemeIcons.FullScreen, .ExitFullScreen, .SeekBackward, .SeekForward, .Volume,
                 ThemeIcons.VolumeMute, .FitView, .ActualSize, .Wrap, .AudioTracks,
                 ThemeIcons.SearchPrevious, .SearchNext, .MatchWholeWord]
    for icon, idx in icons
    {
        let x = 8 + cast(f32) (idx % 5) * 48
        let y = 8 + cast(f32) (idx / 5) * 44
        IconButton.create(&host.root, host.theme.icon(icon, 20), {x, y, 40, 36})
    }

    host.settleAnimations(&host.root, 4)
    var image = host.render(&host.root)
    Pixel.Testing.assertImageGolden(&image, "themeicons.document-media-actions")
}

// The standard appearance action occupies the caption slot immediately before native controls
// and applies both kinds of presentation choice before notifying its owner.
#test
{
    var host: Testing.HeadlessHost
    host.setup(480, 240)
    defer
    {
        discard catch host.app.setLanguage(ReferenceLanguage)
        host.shutdown()
    }

    let button = AppearanceButton.create(&host.surface)
    host.surfaceWnd.sendResizeEvent()
    Swag.assert(button.parent == &host.surfaceWnd)
    Swag.assert(host.surfaceWnd.captionButtons.count == 1)
    Swag.assert(button.position.right() < host.surfaceWnd.clientRect().right())

    var themeChanges, languageChanges, aboutRequests: u32
    button.sigThemeChanged += func|count = &themeChanges|(appearance)
    {
        discard appearance
        count[] += 1
    }
    button.sigLanguageChanged += func|count = &languageChanges|(appearance)
    {
        Swag.assert(appearance.language == "fr")
        count[] += 1
    }
    button.sigAboutRequested += func|count = &aboutRequests|(appearance)
    {
        discard appearance
        count[] += 1
    }

    Swag.assert(button.appearanceTheme == .SwagDark)
    button.setAppearanceTheme(.Dark, notify: true)
    Swag.assert(button.appearanceTheme == .Dark and host.theme.colors.bk == ThemeColors.darkPalette().ground)
    button.setAppearanceTheme(.Light, notify: true)
    Swag.assert(button.appearanceTheme == .Light and host.theme.colors.bk == ThemeColors.lightPalette().ground)
    button.applyAppearanceSelection("Gui.Appearance.Theme.SwagDark")
    Swag.assert(button.appearanceTheme == .SwagDark and host.theme.colors.bk == ThemeColors.swagDarkPalette().ground)
    expect button.setAppearanceLanguage("fr", notify: true)
    Swag.assert(themeChanges == 3 and languageChanges == 1)
    Swag.assert(host.app.language() == "fr")

    button.applyAppearanceSelection("Gui.Appearance.About")
    Swag.assert(aboutRequests == 1)

    button.destroy()
    host.pump()
    Swag.assert(host.surfaceWnd.captionButtons.isEmpty())
}
