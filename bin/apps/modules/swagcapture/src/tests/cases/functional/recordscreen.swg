#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core, Gui

impl Recorder
{
    mtd testChromeGeometry()->{outer: Math.Rectangle, thick: f32, scale: f32} => .chromeGeometry()
}

// The screen chooser moves the live frame and keeps the recording controls on another display.
#test
{
    var f: HeadlessFixture
    f.setup(480, 120)
    defer f.shutdown()

    f.main.monitors.clear()
    testAddMonitorAt(f.main, {0, 0, 800, 600})
    testAddMonitorAt(f.main, {800, 0, 800, 600})

    let recorder = Memory.new'Recorder()
    defer Memory.delete(recorder)
    recorder.main = f.main
    recorder.state = .Preparing
    recorder.videoMode = true
    recorder.screenSelection = true
    recorder.screenIndex = 0
    recorder.area = f.main.monitors[0].physicalBounds
    recorder.target = CaptureTarget.create(recorder.area, 0)

    let width = RecordHud.widthFor(0, recorder.captureLabel(), preparing: true,
                                   screenWidth: RecordHud.screenChoiceWidth(f.main))
    let height = cast(s32, RecordHudHeight + f.gui.theme.metrics.miniBar_ButtonSize + f.gui.theme.metrics.miniBar_Padding)
    let surface = expect f.gui.app.createSurface(0, 0, cast(s32, width), height, .ToolWindow | .TopMost | .Sheet)
    with let hud = RecordHud.create(surface.wnd, recorder)
    {
        .dockStyle = .Center
    }
    recorder.hud = hud
    defer surface.destroy()
    surface.minSize = {}
    surface.setView(hud)
    surface.show()
    surface.wnd.applyLayout()

    let chooser = unwrap hud.screenButton
    Swag.require(chooser is Button and chooser.isEnabled())
    Swag.require(chooser.name.raw.toString() == Format.toString(appStrings().ui_AimScreen, 1))
    Swag.require(recorder.testChromeGeometry().outer == recorder.area and
                 recorder.testChromeGeometry().thick >= RecordFrameWidth)
    hud.follow(recorder.area, 1)
    Swag.require(not surface.position.intersects(recorder.area) and
                 f.main.monitors[1].physicalWorkArea.intersects(surface.position))
    Swag.require(surface.position.x == f.main.monitors[1].physicalWorkArea.x +
                 Math.ceil(RecordHudGap * f.main.monitors[1].scaleFactor))

    f.gui.clickWnd(chooser)
    Swag.require(hud.screenChoices != null, "screen menu did not open")
    let firstMenu = hud.screenChoices.menu
    let menuSurface = unwrap firstMenu.surface
    Swag.require(menuSurface != surface and firstMenu.items.count == 3 and firstMenu.items[0]!.checked)
    Swag.require(menuSurface.app == &f.gui.app and
                 menuSurface.position.width >= firstMenu.position.width and
                 menuSurface.position.height >= firstMenu.position.height)
    // Offscreen GPU hosts cannot route an OS click to a second native surface. The CPU host
    // exercises the pointer path; both hosts check the selection event.
    if Env.variable("SWAG_TEST_RENDERER") == "cpu"
    {
        f.gui.fireTimer(hud.screenChoices.watch)
        Swag.require(firstMenu.mouseCapture() == firstMenu)
        var point = firstMenu.localToSurface(Math.Point{firstMenu.clientRect().horzCenter(),
                                                         firstMenu.items[1]!.pos + firstMenu.items[1]!.size * 0.5})
        menuSurface.surfaceToScreen(&point)
        f.gui.click(point)
        Swag.require(firstMenu.isModalEnded())
        f.gui.fireTimer(hud.screenChoices.watch)
        Swag.require(hud.screenChoices == null)
    }
    else do
        firstMenu.sigCommandSelected.call(firstMenu, "record.screen.1")
    Swag.require(recorder.screenIndex == 1)
    Swag.require(recorder.area == f.main.monitors[1].physicalBounds)
    Swag.require(chooser.name.raw.toString() == Format.toString(appStrings().ui_AimScreen, 2))
    hud.follow(recorder.area, 1)
    Swag.require(not surface.position.intersects(recorder.area) and
                 f.main.monitors[0].physicalWorkArea.intersects(surface.position))
    Swag.require(surface.position.right() == f.main.monitors[0].physicalWorkArea.right() -
                 Math.ceil(RecordHudGap * f.main.monitors[0].scaleFactor))

    f.gui.clickWnd(chooser)
    Swag.require(hud.screenChoices != null)
    let secondMenu = hud.screenChoices.menu
    Swag.require(secondMenu.surface != surface and secondMenu.items.count == 3 and secondMenu.items[1]!.checked)
    if Env.variable("SWAG_TEST_RENDERER") == "cpu"
    {
        f.gui.fireTimer(hud.screenChoices.watch)
        Swag.require(secondMenu.mouseCapture() == secondMenu)
        var point = secondMenu.localToSurface(Math.Point{secondMenu.clientRect().horzCenter(),
                                                          secondMenu.items[2]!.pos + secondMenu.items[2]!.size * 0.5})
        secondMenu.surface!.surfaceToScreen(&point)
        f.gui.click(point)
        Swag.require(secondMenu.isModalEnded())
    }
    else do
        secondMenu.sigCommandSelected.call(secondMenu, AllScreensChoiceId)
    Swag.require(recorder.screenIndex == Swag.U64.Max)
    Swag.require(recorder.area == Math.Rectangle{0, 0, 1600, 600})
    Swag.require(chooser.name.raw.toString() == appStrings().ui_AimAllScreens)
    Swag.require(recorder.testChromeGeometry().outer == recorder.area)
}
