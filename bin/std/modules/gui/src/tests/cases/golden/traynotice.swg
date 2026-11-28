#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core, Pixel

// A detached notice in Papier, including the dismiss cross and the optional preference.
#[Swag.TestTag("golden")]
#test
{
    var host: Testing.HeadlessHost
    host.setup(800, 600)
    defer host.shutdown()

    host.theme.setLight()

    // The fixture pins the card width because the headless monitor follows the machine running it.
    host.theme.metrics.trayNotice_MinWidth = host.theme.metrics.trayNotice_Width
    host.notify(.ThemeChanged)
    let notice = unwrap TrayNotice.open(&host.surface, "Capture continues in the background.", "Open it from the notification area to continue.", "Do not show this message again")
    var image  = host.renderSurface(unwrap notice.surface)
    Pixel.Testing.assertImageGolden(&image, "traynotice.papier")
}
