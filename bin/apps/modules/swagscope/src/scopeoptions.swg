#global internal

using Core, Gui

// The general section of Scope's one options page. Saved credentials stay out of the property grid;
// empty replacement fields leave the user's current credentials untouched.
struct ScopeMediaOptions
{
    #[Properties.Name("Online Movie Posters and Details"), Properties.Description("TMDB first, then Apple and Wikipedia.")]
    onlineMovies: bool

    #[Properties.Name("Online Music Covers and Details"), Properties.Description("MusicBrainz and Cover Art Archive need no API key.")]
    onlineMusic: bool

    #[Properties.Name("Configured TMDB Credentials"), Properties.Description("Credential values are never shown. Enter a replacement below, or leave the fields empty to keep the current credentials."), Properties.ReadOnly(), Properties.EditSize(260)]
    tmdbCredentialStatus: String

    #[Properties.Name("Replace TMDB Read Access Token"), Properties.Description("Saved credentials are not shown. Enter a replacement, or leave empty to keep the current value."), Properties.EditSize(420)]
    tmdbToken: String

    #[Properties.Name("Replace TMDB API Key"), Properties.Description("Saved credentials are not shown. Enter a replacement, or leave empty to keep the current value."), Properties.EditSize(420)]
    tmdbKey: String

    #[Properties.Name("Remove Saved TMDB Credentials"), Properties.Description("Remove the local token and key when this page closes.")]
    clearTMDB: bool
}

impl ViewerWindow
{
    // Creates the searchable general and viewer-owned settings page for the supplied draft.
    mtd createGeneralOptionsDialog(media: *ScopeMediaOptions)->*Dialog
    {
        let dialog = Dialog.create(unwrap .surface, 900, 700, title: appStrings().ui_GeneralOptionsTitle, flags: .Resizable)
        dialog.addButton(Gui.strings().dlg_Cancel, Dialog.BtnCancel)
        dialog.addButton(appStrings().ui_SaveOptions, Dialog.BtnOk, true)

        with let grid = PropertiesCtrl.create(dialog.createContentView(), flags: .SectionNavigation | .SearchBar)
        {
            .dockStyle = .Center
        }
        grid.addStruct(media[], appStrings().explore_MediaOptions)
        for &plugin in .index.plugins where plugin.options do
            plugin.options(grid, plugin.displayName())

        let mediaSection = unwrap grid.list.selectedLine()
        let mediaName = RichString.plainText(mediaSection.items[0]!.name.raw)
        grid.setSectionIcon(mediaName, .theme().icon(.Settings, themeRowIconSize(.themeMetrics())))
        for &plugin in .index.plugins where plugin.options do
            grid.setSectionIcon(plugin.displayName(), .pluginIcon(plugin))

        return dialog
    }

    // The general section and every viewer-owned settings section share one searchable page.
    mtd showGeneralOptions()
    {
        let hasToken = not tmdbStoredCredential("tmdb.token").isEmpty() or
                       not Env.variable("SWAG_SCOPE_TMDB_TOKEN").isEmpty()
        let hasKey   = not tmdbStoredCredential("tmdb.key").isEmpty() or
                       not Env.variable("SWAG_SCOPE_TMDB_KEY").isEmpty()
        var status   = appStrings().ui_TMDBNoneConfigured
        if hasToken and hasKey do
            status = appStrings().ui_TMDBBothConfigured
        elif hasToken do
            status = appStrings().ui_TMDBTokenConfigured
        elif hasKey do
            status = appStrings().ui_TMDBKeyConfigured
        var media = ScopeMediaOptions{onlineMovies: .onlineMovies, onlineMusic: .onlineMusic,
                                      tmdbCredentialStatus: status}
        let oldMarkdown = Viewers.MarkdownText.g_ViewerSettings
        let oldMidi     = Viewers.Midi.g_ViewerSettings
        let oldSubtitle = Viewers.Film.g_SubtitleSettings
        var saved = false
        defer
        {
            if not saved
            {
                Viewers.MarkdownText.g_ViewerSettings = oldMarkdown
                Viewers.Midi.g_ViewerSettings = oldMidi
                Viewers.Film.g_SubtitleSettings = oldSubtitle
            }
        }
        let dialog = .createGeneralOptionsDialog(&media)

        if dialog.doModal() != Dialog.BtnOk do
            return
        let token = Latin1.trim(media.tmdbToken.toString())
        let key   = Latin1.trim(media.tmdbKey.toString())
        if not media.clearTMDB and token.count and not validTMDBToken(token)
        {
            MessageDlg.error(unwrap .surface, appStrings().ui_InvalidTMDBToken)
            return
        }
        if not media.clearTMDB and key.count and not validTMDBKey(key)
        {
            MessageDlg.error(unwrap .surface, appStrings().ui_InvalidTMDBKey)
            return
        }
        catch
        {
            try saveTMDBCredentials(tmdbSettingsDirectory(), token, key, media.clearTMDB)
        }
        {
            MessageDlg.error(unwrap .surface, appStrings().ui_SaveMediaOptionsFailed, Swag.err)
            return
        }

        .onlineMovies = media.onlineMovies
        .onlineMusic  = media.onlineMusic
        Viewers.Film.g_SubtitleSettings.sanitize()
        Viewers.MarkdownText.g_ViewerSettings.sanitize()
        Viewers.Midi.g_ViewerSettings.sanitize()
        if .explorer do
            .explorer.refreshMediaOptions()
        catch .saveState()
        saved = true
    }
}
