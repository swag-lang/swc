#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui, Pixel

// All saved viewer sections share the general page, including when no document is open.
#[Swag.TestTag("golden")]
#test
{
    for light in [false, true]
    {
        var host: Testing.HeadlessHost
        host.setup(1100, 860)
        shipFrame(&host)
        registerAppStrings(&host.app.resources)
        if light do
            host.theme.setLight()
        else do
            host.theme.setDark()
        host.notify(.ThemeChanged)

        let window = ViewerWindow.create(&host.surfaceWnd, createViewerPluginRegistry())
        var media = ScopeMediaOptions{onlineMovies: true, onlineMusic: true}
        let dialog = window.createGeneralOptionsDialog(&media)
        dialog.applyLayout()
        Swag.assert(dialog.surface != null)
        var image = host.renderSurface(dialog.surface)
        Pixel.Testing.assertImageGolden(&image, light ? "options.paper" : "options.ink")
        dialog.surface.destroy()
    }
}

// Local credentials can be replaced and removed without touching the checkout.
#test
{
    let folder = Path.combine(Env.getSpecialDirectory(.Temp), Format.toString("scope-tmdb-options-%", Guid64.random()))
    defer catch Directory.delete(folder, recurse: true)
    let token = "aaa.bbb.cccccccccccccccc"
    let key   = "0123456789abcdef0123456789abcdef"
    Swag.assert(validTMDBToken(token) and validTMDBKey(key))
    expect saveTMDBCredentials(folder, token, key, false)
    Swag.assert(tmdbStoredCredential("tmdb.token", folder) == token)
    Swag.assert(tmdbStoredCredential("tmdb.key", folder) == key)
    expect saveTMDBCredentials(folder, "", "", true)
    Swag.assert(tmdbStoredCredential("tmdb.token", folder).isEmpty())
    Swag.assert(tmdbStoredCredential("tmdb.key", folder).isEmpty())
}
