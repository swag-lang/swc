#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core, Gui, Pixel

// The hub with three recent captures, in Encre: the labelled groups, the row of pictures, then
// the pages of the window.
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
    for index in 3 do
        main.recentWnd.addRecent(Format.toString("recent%.scc", index), testFramePicture(cast(u8, 80 * index), 8 + 12 * cast(s32, index)))

    let panel = testOpenResidentPanel(&host, main, .Centered)
    var image = host.renderSurface(unwrap panel.surface)
    Pixel.Testing.assertImageGolden(&image, "resident.hub.encre")
}

// The keyboard moves through the hub into its recent pictures, with one selected tile in Papier.
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
    for index in 3 do
        main.recentWnd.addRecent(Format.toString("recent%.scc", index), testFramePicture(cast(u8, 80 * index), 8 + 12 * cast(s32, index)))

    let panel       = testOpenResidentPanel(&host, main, .Centered)
    let recents     = unwrap panel.recents
    var down        = KeyEvent{kind: .Pressed, key: .Down}
    var recentGroup = false
    for item in panel.menu.items
    {
        if item!.label and item.name.text == appStrings().lens_Recent do
            recentGroup = true
        if not item.disabled and not item.separator and not item.label
        {
            panel.sendEvent(&down)
            if recentGroup do
                break
        }
    }

    var right = KeyEvent{kind: .Pressed, key: .Right}
    panel.sendEvent(&right)
    panel.sendEvent(&right)
    Swag.require(recents.keyboardIndex == 1)
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

    let panel = testOpenResidentPanel(&host, main, .AtPointer)
    var image = host.renderSurface(unwrap panel.surface)
    Pixel.Testing.assertImageGolden(&image, "resident.menu.papier")
}
