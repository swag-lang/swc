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

    let panel = testOpenResidentPanel(&host, main, .Hub)
    var image = host.renderSurface(unwrap panel.surface)
    Pixel.Testing.assertImageGolden(&image, "resident.hub.encre")
}

// The menu of the notification-area icon on two monitors, in Papier: picture then video
// commands, the cursor and the waits, then the options and the way out.
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
    testAddMonitorAt(main, {1440, 0, 1440, 900})
    main.captureOptions.delay = 5

    let panel = testOpenResidentPanel(&host, main, .Menu)
    var image = host.renderSurface(unwrap panel.surface)
    Pixel.Testing.assertImageGolden(&image, "resident.menu.papier")
}

// The notification near the resident icon in Encre: status, instructions and an opt-out
// checkbox on one floating surface, without modal dialog chrome.
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
    main.editorOptions.language = .French
    main.setLanguage()
    Swag.require(main.noticeResident())
    let notice = unwrap main.residentNotice
    var image = host.renderSurface(unwrap notice.surface)
    Pixel.Testing.assertImageGolden(&image, "resident.notice.encre")
}
