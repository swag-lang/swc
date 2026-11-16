#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core, Gui, Pixel

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
