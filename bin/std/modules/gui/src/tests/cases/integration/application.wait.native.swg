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
            if not surface.isDirty
            {
                settled = true
                break
            }
        }

        Swag.require(settled)
        let frames = app.frameTrace.frames
        for 16 do
            app.runFrame()
        Swag.require(app.frameTrace.frames == frames)
    }

    surface.invalidate()
    Swag.require(app.nativeFrameWaitMicroseconds(0) == 0)
}
