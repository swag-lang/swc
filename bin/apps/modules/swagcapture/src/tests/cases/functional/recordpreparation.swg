#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core, Gui

// Video preparation releases the desktop and gives the live frame one explicit start action.
#test
{
    var f: HeadlessFixture
    f.setup(480, 120)
    defer f.shutdown()

    g_CaptureWindow   = {}
    g_CaptureAnchored = false
    let recorder = Memory.new'Recorder()
    defer Memory.delete(recorder)
    recorder.main      = f.main
    recorder.state     = .Preparing
    recorder.videoMode = true

    let width   = RecordHud.widthFor(0, captureTargetLabel(), preparing: true)
    let height  = cast(s32, RecordHudHeight + f.gui.theme.metrics.miniBar_ButtonSize + f.gui.theme.metrics.miniBar_Padding)
    let surface = expect f.gui.app.createSurface(0, 0, cast(s32, width), height, .ToolWindow | .TopMost | .Sheet)
    with let hud = RecordHud.create(surface.wnd, recorder)
    {
        .dockStyle = .Center
    }
    defer surface.destroy()
    surface.minSize = {}
    surface.setView(hud)
    surface.show()
    surface.wnd.applyLayout()

    var preview = f.gui.renderSurface(surface)
    Swag.require(preview.isValid())
    Swag.require(hud.pauseButton.isEnabled() and not hud.stopButton.isLocallyVisible())
    Swag.require(hud.prepOptions.count == 4)
    let wasCursor = f.main.captureOptions.captureCursor
    let cursor = hud.prepOptions[0]
    let chipCenter = Math.Point{cursor[].position.width * 0.5,
                                cursor[].position.height * 0.5}
    let chipPoint = cursor[].localToSurface(chipCenter)
    let screenPoint = Math.Point{surface.position.x + chipPoint.x * surface.dpiScale,
                                 surface.position.y + chipPoint.y * surface.dpiScale}
    Console.println("HUD hit: body=", hud.surfaceRect(), " chip=", cursor[].surfaceRect(),
                    " point=", screenPoint, " target=", f.gui.mouseTargetAt(screenPoint) == cursor)
    Swag.require(f.gui.mouseTargetAt(screenPoint) == cursor,
                 "recording options must receive pointer events through the surface")
    f.gui.click(screenPoint)
    Swag.require(f.main.captureOptions.captureCursor != wasCursor)
    hud.pauseButton.sigPressed.call(hud.pauseButton)
    Swag.require(recorder.recordRequested)

    recorder.state = .Recording
    preview = f.gui.renderSurface(surface)
    Swag.require(preview.isValid())
    Swag.require(hud.stopButton.isLocallyVisible() and not hud.pauseButton.isEnabled())
}
