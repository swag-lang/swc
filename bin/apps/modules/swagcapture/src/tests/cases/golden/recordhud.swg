#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core, Pixel

// Renders the pill of a recording that stopped after `recorded` microseconds of `limit` (zero for
// none), on its own floating sheet, on a host in Encre or Papier.
func testRenderRecordHud(dark: bool, recorded, limit: u64, dropped: u32 = 0,
                         state = RecorderState.Stopped, screenMode = false)->Image
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
    if screenMode
    {
        f.main.monitors.clear()
        testAddMonitorAt(f.main, {0, 0, 800, 600})
        testAddMonitorAt(f.main, {800, 0, 800, 600})
        recorder.screenSelection = true
        recorder.screenIndex = 0
        recorder.area = f.main.monitors[0].physicalBounds
    }

    // The same sheet the recorder opens, on the host's own application.
    let width    = RecordHud.widthFor(limit, recorder.captureLabel(), state == .Preparing,
                                      screenWidth: screenMode ? RecordHud.screenChoiceWidth(f.main) : 0)
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

// A long screen list is rendered by a menu on its own surface, beyond the HUD's height.
func testRenderScreenChoices()->Image
{
    var f: HeadlessFixture
    f.setup(500, 120)
    defer f.shutdown()
    f.gui.theme.setLight()

    f.main.monitors.clear()
    for index in 8 do
        testAddMonitorAt(f.main, {cast(f32, index) * 800, 0, 800, 600})

    let recorder = Memory.new'Recorder()
    defer Memory.delete(recorder)
    recorder.main = f.main
    recorder.state = .Preparing
    recorder.videoMode = true
    recorder.screenSelection = true
    recorder.area = f.main.monitors[0].physicalBounds

    let width = RecordHud.widthFor(0, recorder.captureLabel(), preparing: true,
                                   screenWidth: RecordHud.screenChoiceWidth(f.main))
    let height = cast(s32, RecordHudHeight + f.gui.theme.metrics.miniBar_ButtonSize + f.gui.theme.metrics.miniBar_Padding)
    let surface = expect f.gui.app.createSurface(0, 0, cast(s32, width), height, .ToolWindow | .TopMost | .Sheet)
    with let hud = RecordHud.create(surface.wnd, recorder)
    {
        .dockStyle = .Center
    }
    surface.minSize = {}
    surface.setView(hud)
    surface.show()
    surface.wnd.applyLayout()

    let choices = unwrap RecordScreenChoices.open(hud, unwrap hud.screenButton)
    Swag.require(choices.menu.items.count == 9)
    var image = f.gui.renderSurface(unwrap choices.surface)
    choices.close()
    surface.destroy()
    return image
}

#[Swag.TestTag("golden")]
#test
{
    var image = testRenderScreenChoices()
    Pixel.Testing.assertImageGolden(&image, "recordhud.screen-choices")
}

// A screen recording exposes its source chooser beside the other preparation options.
#[Swag.TestTag("golden")]
#test
{
    var image = testRenderRecordHud(dark: true, recorded: 0, limit: 0,
                                    state: .Preparing, screenMode: true)
    Pixel.Testing.assertImageGolden(&image, "recordhud.screen-ready")
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
