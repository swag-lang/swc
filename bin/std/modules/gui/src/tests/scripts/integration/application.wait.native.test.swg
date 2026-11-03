#global if #command == Swag.CompilerCommand.Test and #os == Swag.TargetOs.Windows
#global private

// Publishing a native frame must eventually leave the window idle, including after a repaint.
#[Swag.TestTag("integration.host.windows")]
#test
{
    var app: Application
    app.frameTrace.enabled  = true
    app.frameTrace.warmedUp = 20
    let surface = expect app.createSurface(40, 40, 320, 180, surfaceId: "gui-idle-presentation-test")
    surface.show()

    for 2
    {
        surface.invalidate()
        var settled = false
        for 200
        {
            app.runFrame()
            if not surface.isDirty and not surface.readback.isPending()
            {
                settled = true
                break
            }
        }

        Swag.assert(settled)
        let frames = app.frameTrace.frames
        for 16 do
            app.runFrame()
        Swag.assert(app.frameTrace.frames == frames)
    }

    // The fence stays pending until polled, even if the GPU has already finished the copy.
    app.renderer.setCurrentContext(surface.rc)
    Swag.assert(surface.readback.submit(&surface.rt, 0, 0, 1, 1))
    Swag.assert(app.nativeFrameWaitMicroseconds(0) == 1000)
    surface.invalidate()
    Swag.assert(app.nativeFrameWaitMicroseconds(0) == 1000)
    surface.readback.cancel()
    Swag.assert(app.nativeFrameWaitMicroseconds(0) == 0)
}
