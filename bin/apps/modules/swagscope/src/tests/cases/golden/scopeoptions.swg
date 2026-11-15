#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui, Pixel

private func videoSectionCount(wnd: *Wnd)->u32
{
    var count: u32
    if wnd is PropertiesCtrl as grid
    {
        for index in grid.list.lineCount()
        {
            let line = unwrap grid.list.lineAt(index)
            if line.items[0]!.name.text == "Video" do
                count += 1
        }
    }

    for child in wnd.children do
        count += videoSectionCount(child)
    return count
}

// All saved viewer sections share the general page, including when no document is open.
#[Swag.TestTag("golden")]
#test
{
    var host: Testing.HeadlessHost
    host.setup(1100, 860)
    shipFrame(&host)
    registerAppStrings(&host.app.resources)
    host.theme.setLight()
    host.notify(.ThemeChanged)

    let window = ViewerWindow.create(&host.surfaceWnd, createViewerPluginRegistry())
    var media  = ScopeMediaOptions{onlineMovies: true, onlineMusic: true,
                                   movieDetection: Viewers.Film.MovieDetectionSettings.defaults()}
    let dialog = window.createGeneralOptionsDialog(&media)
    dialog.applyLayout()
    Swag.require(videoSectionCount(dialog) == 1)
    Swag.require(dialog.surface != null)
    var image = host.renderSurface(dialog.surface)
    Pixel.Testing.assertImageGolden(&image, "options.paper")
    dialog.surface.destroy()
}
