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

    let icons = [ThemeIcons.Appearance, .OpenFile, .ParentFolder]
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
    @assert(button.parent == &host.surfaceWnd)
    @assert(host.surfaceWnd.captionButtons.count == 1)
    @assert(button.position.right() < host.surfaceWnd.clientRect().right())

    var themeChanges, languageChanges: u32
    button.sigThemeChanged += func|count = &themeChanges|(appearance)
    {
        @assert(appearance.appearanceTheme == .Light)
        count[] += 1
    }
    button.sigLanguageChanged += func|count = &languageChanges|(appearance)
    {
        @assert(appearance.language == "fr")
        count[] += 1
    }

    button.setAppearanceTheme(.Light, notify: true)
    expect button.setAppearanceLanguage("fr", notify: true)
    @assert(themeChanges == 1 and languageChanges == 1)
    @assert(host.app.language() == "fr")

    button.destroy()
    host.pump()
    @assert(host.surfaceWnd.captionButtons.isEmpty())
}
