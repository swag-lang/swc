#global if #command == Swag.CompilerCommand.Test
#global private

// Event-only turns do not count as rendered frames, but their presentation wait still costs time.
#test
{
    var trace: FrameTrace
    trace.enabled   = true
    trace.warmedUp  = 20
    trace.pendingUs = 1000
    trace.beginFrame()
    trace.endFrame()
    Swag.assert(trace.frames == 0 and trace.pendingUs >= 1000)
    trace.beginFrame()
    trace.addSurface(1, 2, 3, 4, 5, 6, 7)
    trace.endFrame()
    Swag.assert(trace.frames == 1 and trace.totalUs >= 1000 and trace.pendingUs == 0)
}
