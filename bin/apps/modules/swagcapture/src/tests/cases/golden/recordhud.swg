#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core, Pixel

// Renders the pill of a recording that stopped after `recorded` microseconds of `limit` (zero for
// none), on its own floating sheet, on a host in Encre or Papier.
func testRenderRecordHud(dark: bool, recorded, limit: u64, dropped: u32 = 0,
                         state = RecorderState.Stopped)->Image
{
    g_CaptureWindow   = {}
    g_CaptureAnchored = false
    var f: HeadlessFixture
    f.setup(400, 120)
    defer f.shutdown()
    if dark do
        f.gui.theme.setDark()
    else do
        f.gui.theme.setLight()

    let recorder = Memory.new'Recorder()
    defer Memory.delete(recorder)
    recorder.main = f.main
    recorder.state    = state
    recorder.videoMode = state == .Preparing
    recorder.clock.recorded = recorded
    recorder.limit    = limit
    recorder.dropped  = dropped

    // The same sheet the recorder opens, on the host's own application.
    let width    = RecordHud.widthFor(limit, captureTargetLabel(), state == .Preparing)
    let height   = cast(s32, RecordHudHeight + (state == .Preparing ? f.gui.theme.metrics.miniBar_ButtonSize + f.gui.theme.metrics.miniBar_Padding : 0))
    let surface  = expect f.gui.app.createSurface(0, 0, cast(s32, width), height, .ToolWindow | .TopMost | .Sheet)
    with let hud = RecordHud.create(surface.wnd, recorder)
    {
        .dockStyle = .Center
    }

    surface.minSize = {}
    surface.setView(hud)
    surface.wnd.applyLayout()
    var image = f.gui.renderSurface(surface)
    surface.destroy()
    return image
}

// The video preparation asks for Record while the live target remains usable.
#[Swag.TestTag("golden")]
#test
{
    var image = testRenderRecordHud(dark: false, recorded: 0, limit: 0, state: .Preparing)
    Pixel.Testing.assertImageGolden(&image, "recordhud.ready")
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

// Missed frames remain visible while recording and have their own visual reference.
#[Swag.TestTag("golden")]
#test
{
    var image = testRenderRecordHud(dark: true, recorded: 7_000_000, limit: 30_000_000, dropped: 12)
    Pixel.Testing.assertImageGolden(&image, "recordhud.dropped")
}
