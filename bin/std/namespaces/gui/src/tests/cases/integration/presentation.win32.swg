#global if #command == Swag.CompilerCommand.Test
#global if #os == Swag.TargetOs.Windows
#global private

using Core, Pixel, Win32, Ogl

// Publish full paints, partial paints and native placements through the window bitmap.
#[Swag.TestTag("integration.host.windows")]
#test
{
    var app: Application
    var icon = Image.create(16, 16, .RGBA8)
    icon.clear()
    app.setAppIcon(#move icon)
    let surface = expect app.createSurface(40, 40, 360, 240, surfaceId: "gui-layered-presentation-test")
    let button  = PushButton.create(surface.wnd.view, "Probe", {32, 32, 84, 32})
    Swag.require(GetWindowLongPtrW(surface.win32Handle(), GWL_EXSTYLE) & WS_EX_LAYERED)
    surface.show()
    Swag.require(app.appGlyph(16).isValid())
    Swag.require(expect Testing.verifyNativePresentation(surface))

    app.frameTrace.enabled = true
    surface.isDirty        = false

    // Change the paint output while keeping this test independent of relayout.
    button.name.set("Changed")
    button.invalidate()
    surface.paint()
    Swag.require(surface.paintArea < cast(u64, surface.rc.width) * cast(u64, surface.rc.height))
    Swag.require(expect Testing.verifyNativePresentation(surface))

    // A size change publishes a complete bitmap after a partial redraw.
    surface.setPosition({60, 50, 420, 280})
    Swag.require(surface.position == {60, 50, 420, 280})
    Swag.require(not surface.presentedFrame)
    app.runFrame()
    Swag.require(expect Testing.verifyNativePresentation(surface))

    var bounds: RECT
    Swag.require(GetWindowRect(surface.win32Handle(), &bounds))
    Swag.require(bounds.left == 60 and bounds.top == 50 and bounds.right == 480 and bounds.bottom == 330)
    surface.showNormalAt({75, 60, 399, 271})
    Swag.require(not surface.isDirty)
    Swag.require(expect Testing.verifyNativePresentation(surface))

    // A failed submission schedules a complete repaint and leaves the previous frame visible.
    var inject = true
    surface.wnd.view.hookOnEvent = func|&inject|(_, evt)->bool
    {
        if inject and evt is PaintEvent
        {
            glScissor(0, 0, 1, -1)
            inject = false
        }

        return false
    }

    surface.invalidate()
    surface.paint()
    Swag.require(not surface.renderFailure.isEmpty() and surface.isDirty)
    surface.paint()
    Swag.require(surface.renderFailure.isEmpty())
    Swag.require(expect Testing.verifyNativePresentation(surface))
}
