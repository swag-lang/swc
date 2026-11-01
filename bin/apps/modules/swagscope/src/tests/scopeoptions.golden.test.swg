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
        var media  = ScopeMediaOptions{onlineMovies: true, onlineMusic: true}
        let dialog = window.createGeneralOptionsDialog(&media)
        dialog.applyLayout()
        Swag.assert(dialog.surface != null)
        var image = host.renderSurface(dialog.surface)
        Pixel.Testing.assertImageGolden(&image, light ? "options.paper" : "options.ink")
        dialog.surface.destroy()
    }
}
