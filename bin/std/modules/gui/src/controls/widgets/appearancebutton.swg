#global public

using Core, Pixel

// Selects one of the three palettes shipped by standard Swag applications.
enum AppearanceTheme
{
    SwagDark = 0     // Uses the dark Swag palette.
    Dark     = 2     // Uses the neutral dark palette.
    Light    = 1     // Uses the neutral light palette.
}

// Hosts the standard theme, language, and application-information menu in a title bar.
//
// An empty [[language]] follows the user account. A non-empty value is a tag registered through
// [[Gui.registerLanguage]]. The control applies both choices before emitting their signals, so an
// application only has to persist them and refresh state derived from the palette. The About item
// is present when [[sigAboutRequested]] has a callback.
struct AppearanceButton
{
    public
    {
        using button: IconButton     // Embedded icon-button behavior and presentation.

        sigThemeChanged:    SigArray'func||(*AppearanceButton)     // Emitted after the user changes the theme.
        sigLanguageChanged: SigArray'func||(*AppearanceButton)     // Emitted after the user changes the language.
        sigAboutRequested:  SigArray'func||(*AppearanceButton)     // Emitted after the user chooses the About item.

        readonly
        {
            appearanceTheme = AppearanceTheme.SwagDark     // Theme currently selected by the control.
            language: String                               // Registered language tag, or empty to follow the system.
        }
    }
}

private const AppearanceThemeSwagDarkId = "Gui.Appearance.Theme.SwagDark"
private const AppearanceThemeDarkId     = "Gui.Appearance.Theme.Dark"
private const AppearanceThemeLightId    = "Gui.Appearance.Theme.Light"
private const AppearanceLanguageSysId   = "Gui.Appearance.Language.System"
private const AppearanceAboutId         = "Gui.Appearance.About"

impl IWnd for AppearanceButton
{
    mtd impl onDestroyEvent(evt: *DestroyEvent)
    {
        (cast(*SurfaceWnd) .parent!).unregisterCaptionButton(me)
        .button.IWnd.onDestroyEvent(evt)
    }

    mtd impl onNotifyEvent(evt: *NotifyEvent)
    {
        if evt.kind == .LanguageChanged do
            .toolTip = strings().appearance_ToolTip
        evt.accepted = false
    }
}

impl AppearanceButton
{
    // Creates the standard application appearance action immediately before the native caption
    // buttons. Register every supported language before calling this function.
    #[Swag.Discardable]
    func create(surface: *Surface, id: #null WndId = null)->*AppearanceButton
    {
        let parent      = cast(*SurfaceWnd) surface.wnd
        with let result = Wnd.create'AppearanceButton(parent, null, {}, id)
        {
            .button.setIcon(surface.app.theme.icon(.Appearance, surface.app.theme.metrics.wnd_CaptionButtonGlyph))
            .setForm(.RoundedRectangle)
            .focusPolicy = .None
            .toolTip     = strings().appearance_ToolTip
            .sigPressed  += func(button)
            {
                (cast(*AppearanceButton) button).showAppearanceMenu()
            }
        }

        parent.registerCaptionButton(result)
        return result
    }

    // Applies `theme` and optionally reports a user-visible choice.
    mtd setAppearanceTheme(theme: AppearanceTheme, notify = false)
    {
        .appearanceTheme = theme
        switch #complete theme
        {
        case .SwagDark: .app().theme.setSwagDark()
        case .Dark:     .app().theme.setDark()
        case .Light:    .app().theme.setLight()
        }

        .app().notifyThemeChanged()
        if notify do
            .sigThemeChanged.call(me)
    }

    // Applies a registered language tag, or follows the system when `tag` is empty, and optionally
    // reports a user-visible choice. The stored choice changes only after resources were applied.
    mtd setAppearanceLanguage(tag: string, notify = false) fail
    {
        let resolved = @countof(tag) ? tag : systemLanguage()
        try .app().setLanguage(resolved)
        .language = tag
        .toolTip  = strings().appearance_ToolTip
        if notify do
            .sigLanguageChanged.call(me)
    }

    private mtd showAppearanceMenu()
    {
        let root = .createAppearanceMenu()
        let rect = .surfaceRect()
        .applyAppearanceSelection(root.doModal({rect.horzCenter(), rect.bottom()}, .AnchorTopCenter, autoDestroy: true))
    }

    private mtd createAppearanceMenu()->*MenuCtrl
    {
        let root = MenuCtrl.createPopup(me, owner: me)
        root.updateFlags(.HideShortcuts)

        let themes = MenuCtrl.createPopup(root, owner: me)
        themes.addItem(strings().appearance_SwagDark, AppearanceThemeSwagDarkId, checked: .appearanceTheme == .SwagDark)
        themes.addItem(strings().appearance_Dark, AppearanceThemeDarkId, checked: .appearanceTheme == .Dark)
        themes.addItem(strings().appearance_Light, AppearanceThemeLightId, checked: .appearanceTheme == .Light)
        root.addPopup(strings().appearance_Theme, themes)

        let languageMenu = MenuCtrl.createPopup(root, owner: me)
        languageMenu.addItem(strings().appearance_SystemLanguage, AppearanceLanguageSysId, checked: .language.isEmpty())
        for &one in languages() do
            languageMenu.addItem(one.nativeName.toString(), one.tag.toString(), checked: !.language.isEmpty() and one.tag == .language)
        root.addPopup(strings().appearance_Language, languageMenu)

        if !.sigAboutRequested.isEmpty()
        {
            root.addSeparator()
            root.addItem(strings().appearance_About, AppearanceAboutId, icon: .theme().icon(.About))
        }

        return root
    }

    internal mtd applyAppearanceSelection(selected: #null WndId)
    {
        if selected == AppearanceThemeSwagDarkId do
            .setAppearanceTheme(.SwagDark, notify: true)
        elif selected == AppearanceThemeDarkId do
            .setAppearanceTheme(.Dark, notify: true)
        elif selected == AppearanceThemeLightId do
            .setAppearanceTheme(.Light, notify: true)
        elif selected == AppearanceLanguageSysId do
            discard catch .setAppearanceLanguage("", notify: true)
        elif selected == AppearanceAboutId do
            .sigAboutRequested.call(me)
        elif selected and findLanguage(selected!) do
            discard catch .setAppearanceLanguage(selected!, notify: true)
    }
}
