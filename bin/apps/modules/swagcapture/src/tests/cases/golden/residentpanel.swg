#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core, Gui, Pixel

// The compact startup hub in Encre, with the default picture destination.
#[Swag.TestTag("golden")]
#test
{
    var host: Testing.HeadlessHost
    let main = testSetupSurfaceMain(&host)
    defer
    {
        host.shutdown()
        g_Main = null
    }

    host.theme.setDark()
    host.notify(.ThemeChanged)
    let panel = testOpenResidentPanel(&host, main, .Centered)
    var image = host.renderSurface(unwrap panel.surface)
    Pixel.Testing.assertImageGolden(&image, "resident.hub.encre")
}

// The keyboard selects the active-window capture beside the latest copied image in Papier.
#[Swag.TestTag("golden")]
#test
{
    var host: Testing.HeadlessHost
    let main = testSetupSurfaceMain(&host)
    defer
    {
        host.shutdown()
        g_Main = null
    }

    host.theme.setLight()
    host.notify(.ThemeChanged)
    main.clipboardPreview = testFramePicture(80, 8)
    let panel = testOpenResidentPanel(&host, main, .Centered)
    var home  = KeyEvent{kind: .Pressed, key: .Home}
    var down  = KeyEvent{kind: .Pressed, key: .Down}
    panel.sendEvent(&home)
    panel.sendEvent(&down)
    panel.sendEvent(&down)
    Swag.require(down.accepted)
    var image = host.renderSurface(unwrap panel.surface)
    Pixel.Testing.assertImageGolden(&image, "resident.hub.keyboard.papier")
}

// The same home opened from the notification-area icon, in French and Papier on two monitors.
#[Swag.TestTag("golden")]
#test
{
    var host: Testing.HeadlessHost
    let main = testSetupSurfaceMain(&host)
    defer
    {
        host.shutdown()
        g_Main = null
    }

    host.theme.setLight()
    host.notify(.ThemeChanged)
    defer discard catch host.app.setLanguage(Gui.ReferenceLanguage)
    expect host.app.setLanguage("fr")
    testAddMonitorAt(main, {1440, 0, 1440, 900})
    main.captureOptions.delay         = 5
    main.captureOptions.captureCursor = true
    main.clipboardPreview             = testFramePicture(135, 30)

    let panel = testOpenResidentPanel(&host, main, .AtPointer)
    var image = host.renderSurface(unwrap panel.surface)
    Pixel.Testing.assertImageGolden(&image, "resident.menu.papier")
}

// The second page groups the extra targets, and distinguishes individual displays from video.
#[Swag.TestTag("golden")]
#test
{
    var host: Testing.HeadlessHost
    let main = testSetupSurfaceMain(&host)
    defer
    {
        host.shutdown()
        g_Main = null
    }

    host.theme.setDark()
    host.notify(.ThemeChanged)
    testAddMonitorAt(main, {1440, 0, 1440, 900})
    main.captureOptions.pictureDestination = .Clipboard

    let panel = testOpenResidentPanel(&host, main, .Centered)
    panel.choose(ResidentPanel.MoreCaptures)
    var image = host.renderSurface(unwrap panel.surface)
    Pixel.Testing.assertImageGolden(&image, "resident.othercaptures.encre")
}
