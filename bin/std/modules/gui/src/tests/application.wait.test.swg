#global if #command == Swag.CompilerCommand.Test and #os == Swag.TargetOs.Windows
#global private

// Quiet turns yield without imposing that delay on pending paints or active gestures.
#test
{
    var app: Application
    Swag.assert(app.nativeFrameWaitMicroseconds(0) == 16000)
    Swag.assert(app.nativeFrameWaitMicroseconds(5000) == 11000)
    Swag.assert(app.nativeFrameWaitMicroseconds(16000) == 0)
    Swag.assert(app.nativeFrameWaitMicroseconds(20000) == 0)

    let target = Core.Memory.new'Wnd()
    defer Core.Memory.delete(target)
    app.setMouseCaptureRaw(target)
    Swag.assert(app.nativeFrameWaitMicroseconds(0) == 1000)
    Swag.assert(app.nativeFrameWaitMicroseconds(1000) == 0)
    app.setMouseCaptureRaw(null)

    app.frameTrace.busyLoop = true
    Swag.assert(app.nativeFrameWaitMicroseconds(0) == 0)
}

// A short timer wakes before the idle interval; retiring it restores the quiet cadence.
#test
{
    var app: Application
    let target = Core.Memory.new'Wnd()
    defer Core.Memory.delete(target)
    let timer = app.addTimer(2'ms, target)
    Swag.assert(app.nativeFrameWaitMicroseconds(0) == 2000)
    timer.isPendingRemoval = true
    Swag.assert(app.nativeFrameWaitMicroseconds(0) == 16000)
    timer.isPendingRemoval = false
    app.removeTimer(timer)
    Swag.assert(app.nativeFrameWaitMicroseconds(0) == 16000)
}

// A visible dirty surface bypasses the wait, but hidden and minimized surfaces do not spin.
#test
{
    var host: Testing.HeadlessHost
    host.setup(240, 120)
    defer host.shutdown()
    host.surface.show()
    host.surface.isDirty = true
    Swag.assert(host.app.nativeFrameWaitMicroseconds(0) == 0)
    host.surface.hide()
    Swag.assert(host.app.nativeFrameWaitMicroseconds(0) == 16000)
    host.surface.show()
    host.surface.requestMinimize()
    host.app.runFrame()
    Swag.assert(host.app.nativeFrameWaitMicroseconds(0) == 16000)
}
