using Core, Gui

// A monitor-sized host keeps capture shortcuts together on one screen of the virtual desktop.
struct CaptureHints
{
    using wnd: Wnd

    late main: *MainWnd
    late line: *HintLine
}

impl CaptureHints
{
    func create(parent: *Wnd, main: *MainWnd)->*CaptureHints
    {
        with let result = Wnd.create'CaptureHints(parent)
        {
            .main = main
            .line = HintLine.create(result)

            // The host supplies layout bounds; interactive siblings keep the pointer.
            .enable(false)
            .sendToBack()
        }

        return result
    }

    // Places the shortcuts within the monitor containing `point`, in physical screen pixels.
    mtd placeAt(point: Math.Point)
    {
        let parent  = unwrap .parent
        var bounds  = parent.clientRect()
        var screenRoom: Math.Rectangle
        var nearest = Swag.F32.Max
        for monitor in .main.monitors
        {
            let screen   = monitor.physicalBounds
            let dx       = point.x - Math.clamp(point.x, screen.x, screen.right())
            let dy       = point.y - Math.clamp(point.y, screen.y, screen.bottom())
            let distance = dx * dx + dy * dy
            if distance >= nearest do
                continue
            nearest    = distance
            screenRoom = monitor.physicalWorkArea
        }

        if not screenRoom.isEmpty()
        {
            var origin = screenRoom.topLeft()
            .surface?.screenToSurface(&origin)
            origin = parent.surfaceToLocal(origin)
            let scale = parent.deviceScale()
            bounds = {origin.x, origin.y, screenRoom.width / scale, screenRoom.height / scale}
            bounds.intersect(parent.clientRect())
        }

        .setPosition(bounds)
        .line.itf.onLayout()
    }
}
