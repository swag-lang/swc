#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core, Pixel

// Renders the pill of a recording that stopped after `recorded` microseconds of `limit` (zero for
// none), on its own floating sheet, on a host in Encre or Papier.
func testRenderRecordHud(dark: bool, recorded, limit: u64)->Image
{
    var host: Gui.Testing.HeadlessHost
    host.setup(400, 120)
    host.bindApplication(&g_App)
    defer host.shutdown()
    if dark do
        host.theme.setDark()
    else do
        host.theme.setLight()

    let recorder = Memory.new'Recorder()
    defer Memory.delete(recorder)
    recorder.state    = .Stopped
    recorder.recorded = recorded
    recorder.limit    = limit

    // The same sheet the recorder opens, on the host's own application.
    let width    = RecordHud.widthFor(limit)
    let surface  = expect host.app.createSurface(0, 0, cast(s32, width), cast(s32, RecordHudHeight), .ToolWindow | .TopMost | .Sheet)
    with let hud = RecordHud.create(surface.wnd, recorder)
    {
        .dockStyle = .Center
    }

    surface.minSize = {}
    surface.setView(hud)
    surface.wnd.applyLayout()
    var image = host.renderSurface(surface)
    surface.destroy()
    return image
}

// A limited recording: the ring fills towards the limit, the limit follows the time.
#[Swag.TestTag("golden")]
#test
{
    var image = testRenderRecordHud(dark: true, recorded: 7_000_000, limit: 30_000_000)
    Pixel.Testing.assertImageGolden(&image, "recordhud")
}

// A recording without a limit shows the time alone, past an hour here.
#[Swag.TestTag("golden")]
#test
{
    var image = testRenderRecordHud(dark: false, recorded: 3_727_000_000, limit: 0)
    Pixel.Testing.assertImageGolden(&image, "recordhud.unlimited")
}
