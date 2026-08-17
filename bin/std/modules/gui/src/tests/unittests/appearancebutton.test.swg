#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

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
