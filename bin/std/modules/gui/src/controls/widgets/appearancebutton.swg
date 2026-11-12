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

private const AppearanceDarkCommand           = "Gui.Appearance.Theme.Dark"
private const AppearanceLightCommand          = "Gui.Appearance.Theme.Light"
private const AppearanceSystemCommand         = "Gui.Appearance.Theme.System"
private const AppearanceSystemLanguageCommand = "Gui.Appearance.Language.System"

private struct AppearanceLanguageCommand
{
    id:  String
    tag: String
}

private var g_AppearanceLanguageCommands: Array'AppearanceLanguageCommand

// Routes registered theme and language choices through the same state and command events as
// every application action. The surface owns the AppearanceButton that applies each choice.
internal struct ActionAppearance {}

internal impl IActionUI for ActionAppearance
{
    mtd impl accept(cxt: ActionContext)->bool => appearanceThemeCommandIndex(cxt.id) != Swag.U32.Max or
                                                  cxt.id == AppearanceSystemLanguageCommand or
                                                  appearanceLanguageForCommand(cxt.id) != null

    mtd impl update(cxt: ActionContext, evt: *CommandStateEvent)->bool
    {
        let button = assume cast (*SurfaceWnd, cxt.wnd).appearanceButton
        if not button do
            return false

        evt.updatedFields |= .Name | .Checked | .RenderingHint
        evt.renderingHint = .ExclusiveGroup

        let themeIndex = appearanceThemeCommandIndex(cxt.id)
        if themeIndex != Swag.U32.Max
        {
            let theme   = AppearanceThemeValues[themeIndex]
            evt.name    = appearanceThemeName(theme)
            evt.checked = button.appearanceTheme == theme
            return true
        }

        if cxt.id == AppearanceSystemLanguageCommand
        {
            evt.name    = strings().appearance_SystemLanguage
            evt.checked = button.language.isEmpty()
            return true
        }

        if let choice = appearanceLanguageForCommand(cxt.id)
        {
            evt.name    = findLanguage(choice.tag)?.nativeName.toString() orelse choice.tag.toString()
            evt.checked = button.language == choice.tag
            return true
        }

        return false
    }

    mtd impl execute(cxt: ActionContext)->bool
    {
        let button = assume cast (*SurfaceWnd, cxt.wnd).appearanceButton
        if not button do
            return false

        let themeIndex = appearanceThemeCommandIndex(cxt.id)
        if themeIndex != Swag.U32.Max
        {
            button.setAppearanceTheme(AppearanceThemeValues[themeIndex], notify: true)
            return true
        }

        if cxt.id == AppearanceSystemLanguageCommand
        {
            discard catch button.setAppearanceLanguage("", notify: true)
            return true
        }

        if let choice = appearanceLanguageForCommand(cxt.id)
        {
            discard catch button.setAppearanceLanguage(choice.tag, notify: true)
            return true
        }

        return false
    }
}

impl IWnd for AppearanceButton
{
    mtd impl onDestroyEvent(evt: *DestroyEvent)
    {
        let parent = assume cast (*SurfaceWnd, .parent)
        parent.unregisterCaptionButton(me)
        if parent.appearanceButton == me do
            parent.appearanceButton = null
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
            .appearanceTheme = surface.app.appearance
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
        if not parent.appearanceActionRegistered
        {
            parent.registerAction'ActionAppearance()
            parent.appearanceActionRegistered = true
        }
        parent.appearanceButton = result
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

    // Opens the theme, language and application information beside this button.
    //
    // Changes apply as soon as they are chosen, so the open sheet redraws in the new theme or language.
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

    // Offers the theme, language and About box as rows of `lens` and registers menu choices.
    //
    // The lens shows themes and languages as exclusive segments; a query naming a group lists
    // all its choices. The same choices are registered as commands for an optional application
    // menu, where they appear under Theme and Language submenus. Each menu entry reports its
    // current selection and applies it through this button. About remains a lens row when
    // [[Gui.AppearanceButton.sigAboutRequested]] has a callback.
    mtd addToLens(lens: *Lens.View)
    {
        lens.addSource(.None, func|button = me|(results) { button.describeLens(results) })
        lens.addCommands(func()->string => strings().lens_Application,
                         [AppearanceDarkCommand, AppearanceLightCommand, AppearanceSystemCommand],
                         menuGroup: func()->string => strings().appearance_Theme,
                         menuSection: 1, inLens: false)
        lens.addCommand(func()->string => strings().lens_Application, AppearanceSystemLanguageCommand,
                        menuGroup: func()->string => strings().appearance_Language,
                        menuSection: 1, inLens: false)
        for &one in languages() do
            lens.addCommand(func()->string => strings().lens_Application, appearanceLanguageCommandId(one.tag),
                            menuGroup: func()->string => strings().appearance_Language,
                            menuSection: 1, inLens: false)
    }

    internal mtd describeLens(results: *Lens.Results)
    {
        let texts = strings()
        let query = results.query.toString()

        var themes: *Lens.Section?
        for theme in [AppearanceTheme.Dark, .Light, .System]
        {
            let name = appearanceThemeName(theme)
            if not lensAnswers(query, name, texts.appearance_Theme) do
                continue
            if not themes
            {
                themes        = results.addSection(texts.appearance_Theme)
                themes.inline = true
            }

            with let entry = themes.addEntry(name)
            {
                .checked = theme == me.appearanceTheme
                .run     = func|button = me, theme|() { button.setAppearanceTheme(theme, notify: true) }
            }
        }

        var choices: *Lens.Section?
        if lensAnswers(query, texts.appearance_SystemLanguage, texts.appearance_Language)
        {
            choices        = results.addSection(texts.appearance_Language)
            choices.inline = true
            with let entry = choices.addEntry(texts.appearance_SystemLanguage)
            {
                .checked = me.language.isEmpty()
                .run     = func|button = me|() { discard catch button.setAppearanceLanguage("", notify: true) }
            }
        }

        for &one in languages()
        {
            let name = one.nativeName.toString()
            if not lensAnswers(query, name, texts.appearance_Language) do
                continue
            if not choices
            {
                choices        = results.addSection(texts.appearance_Language)
                choices.inline = true
            }

            let tag        = one.tag.toString()
            with let entry = choices.addEntry(name)
            {
                .checked = one.tag == me.language
                .run     = func|button = me, tag|() { discard catch button.setAppearanceLanguage(tag, notify: true) }
            }
        }

        if not .sigAboutRequested.isEmpty() and lensAnswers(query, texts.appearance_About, texts.lens_Application)
        {
            with let entry = results.addSection(texts.lens_Application).addEntry(texts.appearance_About)
            {
                .run = func|button = me|() { button.sigAboutRequested.call(button) }
            }
        }
    }
}

// Reports whether `query` answers a row titled `title` or the group `group` it belongs to.
private func lensAnswers(query, title, group: string)->bool => Lens.match(query, title).matched or Lens.match(query, group).matched

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

private func appearanceThemeCommandIndex(id: WndId)->u32
{
    switch id
    {
    case AppearanceDarkCommand:   return 0
    case AppearanceLightCommand:  return 1
    case AppearanceSystemCommand: return 2
    }

    return Swag.U32.Max
}

private func appearanceLanguageCommandId(tag: string)->WndId
{
    for &choice in g_AppearanceLanguageCommands where choice.tag == tag do
        return choice.id

    g_AppearanceLanguageCommands.add(AppearanceLanguageCommand{
        Format.toString("Gui.Appearance.Language.%", tag), String.from(tag)})
    return g_AppearanceLanguageCommands[g_AppearanceLanguageCommands.count - 1].id
}

private func appearanceLanguageForCommand(id: WndId)->const *AppearanceLanguageCommand?
{
    for &choice in g_AppearanceLanguageCommands where choice.id == id do
        return choice
    return null
}
