#global public

using Core, Pixel

// Hosts the standard theme, language, and application-information options in a title bar.
//
// An empty [[Gui.AppearanceButton.language]] follows the user account. A non-empty value is a tag registered through
// [[Gui.registerLanguage]]. The control applies both choices before emitting their signals, so an
// application only has to persist them and refresh state derived from the palette. The About item
// is present when [[Gui.AppearanceButton.sigAboutRequested]] has a callback.
struct AppearanceButton
{
    public
    {
        using button: IconButton     // Embedded icon-button behavior and presentation.

        sigThemeChanged:    SigArray'func||(*Wnd)     // Emitted after the user changes the theme.
        sigLanguageChanged: SigArray'func||(*Wnd)     // Emitted after the user changes the language.
        sigAboutRequested:  SigArray'func||(*Wnd)     // Emitted after the user chooses the About item.

        readonly
        {
            appearanceTheme = AppearanceTheme.Dark     // Theme currently selected by the control.
            language: String     // Registered language tag, or empty to follow the system.
        }
    }
}

impl IWnd for AppearanceButton
{
    mtd impl onDestroyEvent(evt: *DestroyEvent)
    {
        assume cast (*SurfaceWnd, .parent).unregisterCaptionButton(me)
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
    // Creates the standard appearance button in the caption bar of `surface`, before its native caption buttons.
    //
    // Register every supported language before calling this function.
    #[Swag.Discardable]
    func create(surface: *Surface, id: WndId? = null)->*AppearanceButton
    {
        let parent      = assume cast (*SurfaceWnd, surface.wnd)
        with let result = Wnd.create'AppearanceButton(parent, null, {}, id)
        {
            .button.setIcon(surface.app.theme.icon(.Appearance, surface.app.theme.metrics.wnd_CaptionButtonGlyph))
            .setForm(.RoundedRectangle)
            .focusPolicy = .None
            .toolTip     = strings().appearance_ToolTip
            .sigPressed  += func(button)
            {
                assume cast (*AppearanceButton, button).showAppearanceOptions()
            }
        }

        parent.registerCaptionButton(result)
        return result
    }

    // Applies `theme` to the application and, when `notify` is true, emits [[Gui.AppearanceButton.sigThemeChanged]].
    //
    // See [[Gui.Application.setAppearance]]: [[Gui.AppearanceTheme.System]] keeps following the
    // operating system while the application runs.
    mtd setAppearanceTheme(theme: AppearanceTheme, notify = false)
    {
        .appearanceTheme = theme
        .app().setAppearance(theme)
        if notify do
            .sigThemeChanged.call(me)
    }

    // Applies the registered language `tag`, or the system language when `tag` is empty.
    //
    // When `notify` is true, emits [[Gui.AppearanceButton.sigLanguageChanged]]. The stored choice
    // changes only after the resources were applied, so a failure leaves it unchanged.
    mtd setAppearanceLanguage(tag: string, notify = false) fail
    {
        let resolved = tag.count ? tag : systemLanguage()
        try .app().setLanguage(resolved)
        .language = tag
        .toolTip  = strings().appearance_ToolTip
        if notify do
            .sigLanguageChanged.call(me)
    }

    // Opens the theme, the language and the information about the application below the button.
    //
    // A theme or a language applies as soon as it is chosen, so the sheet itself is redrawn in it
    // and the reader sees the choice before closing.
    private mtd showAppearanceOptions()
    {
        let sheet = OptionSheet.View.create(me, func|button = me|(page) { button.describeAppearance(page) }, owner: me)
        sheet.doModal(me, autoDestroy: true)
    }

    internal mtd describeAppearance(page: *OptionSheet.Page)
    {
        let texts    = strings()
        let iconSize = themeRowIconSize(.themeMetrics())
        page.addLink(texts.appearance_Theme,
                     appearanceThemeName(.appearanceTheme),
                     func|button = me|(themes)
                     {
                         for theme in [AppearanceTheme.Dark, .Light, .System] do
                             themes.addChoice(appearanceThemeName(theme), theme == button.appearanceTheme, func|button, theme|() { button.setAppearanceTheme(theme, notify: true) })
                     },
                     .theme().icon(.Appearance, iconSize))

        let language = .language.isEmpty() ? texts.appearance_SystemLanguage : (findLanguage(.language)?.nativeName.toString() orelse .language.toString())
        page.addLink(texts.appearance_Language,
                     language,
                     func|button = me|(choices)
                     {
                         choices.addChoice(strings().appearance_SystemLanguage, button.language.isEmpty(), func|button|()
                         {
                             discard catch button.setAppearanceLanguage("", notify: true)
                         })

                         for &one in languages()
                         {
                             let tag = one.tag.toString()
                             choices.addChoice(one.nativeName.toString(), one.tag == button.language, func|button, tag|()
                             {
                                 discard catch button.setAppearanceLanguage(tag, notify: true)
                             })
                         }
                     },
                     .theme().icon(.Information, iconSize))

        if not .sigAboutRequested.isEmpty() do
            page.addAction(texts.appearance_About, func|button = me|() { button.sigAboutRequested.call(button) }, closesSheet: true)
    }
}

// Names one appearance in the language of the interface.
private func appearanceThemeName(theme: AppearanceTheme)->string
{
    switch #complete theme
    {
    case .Dark:   return strings().appearance_Dark
    case .Light:  return strings().appearance_Light
    case .System: return strings().appearance_System
    }
}
