#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Pixel, Gui

// The home lists the last six files, quietly: the faint glyph of the kind, the name, the time; the
// row under the pointer names its folder and offers its removal. The Clear menu button stays
// visible below the history. One picture at rest and in use.
#[Swag.TestTag("golden")]
#test
{
    let light = true
    var host: Testing.HeadlessHost
    let window = homeWindow(&host, light)
    Swag.assert(window.home.isLocallyVisible() and window.home.rows.count == 6)
    Swag.assert(ViewerHome.openedText(window.home.rows[0].opened, HomeNow) == "17:42")
    Swag.assert(ViewerHome.openedText(window.home.rows[3].opened, HomeNow) == appStrings().home_Yesterday)
    var rest = host.renderSettled(window)
    Pixel.Testing.assertImageGolden(&rest, "home.paper")

    host.moveMouse(window.home.localToSurface(window.home.rowRect(1).center()))
    Swag.assert(window.home.hovered == 1 and window.home.pointerIn)
    window.home.invalidate()
    var hover = host.render(window)
    Swag.assert(window.home.hovered == 1 and window.home.pointerIn)
    Pixel.Testing.assertImageGolden(&hover, "home.hover.paper")
}
