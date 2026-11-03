#global if #command == Swag.CompilerCommand.Test
#global internal

using Swag, Core, Pixel

// Builds a window of `width` by `height` on the theme of `light`, with a sheet of paper standing
// for the work in its middle, so a floating component reads against something it covers.
func floatingHost(host: *Testing.HeadlessHost, width, height: f32, light: bool)
{
    host.setup(width, height)
    if light
    {
        host.theme.setLight()
        host.notify(.ThemeChanged)
    }

    host.root.backgroundStyle = .Window
    with let work = Wnd.create'Wnd(&host.root, {width * 0.25, height * 0.2, width * 0.5, height * 0.5})
    {
        .backgroundStyle = .Dialog
    }
}
