#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

// The same caption glyph must read much quieter when unavailable in both shipped palettes.
#test
{
    for light in [false, true]
    {
        var host: Testing.HeadlessHost
        host.setup(480, 240)
        host.surface.flags = SurfaceFlags.StandardWindow
        if light
        {
            host.theme.setLight()
            host.notify(.ThemeChanged)
        }

        host.surfaceWnd.create(&host.root, null)
        let unavailable = CaptionButton.createLeading(&host.surface, .ChevronLeft)
        let available   = CaptionButton.createLeading(&host.surface, .ChevronLeft)
        unavailable.disable()
        host.surfaceWnd.sendResizeEvent()
        Swag.require(not unavailable.isEnabled() and available.isEnabled())

        let image  = host.renderSettled(&host.surfaceWnd)
        let ground = host.theme.colors.wnd_Bk
        var peaks: [2] f32
        for button, index in [unavailable, available]
        {
            let rect = button.surfaceRect()
            for y in cast(s32, rect.y) until cast(s32, rect.bottom()) do
                for x in cast(s32, rect.x) until cast(s32, rect.right()) do
                    peaks[index] = Math.max(peaks[index], image.pixelColor(x, y).contrastRatio(ground))
        }

        Swag.require(peaks[1] >= peaks[0] * 1.7)
    }
}

#test
{
    var host: Testing.HeadlessHost
    host.setup(480, 240)
    host.surface.flags = SurfaceFlags.StandardWindow
    host.surfaceWnd.create(&host.root, null)
    host.surfaceWnd.sendResizeEvent()

    let button = CaptionButton.create(&host.surface, ThemeIcons.Settings)
    Swag.require(host.surfaceWnd.captionButtons.count == 1)
    Swag.require(button.parent == &host.surfaceWnd)
    Swag.require(button.icon.index == cast(s32, ThemeIcons.Settings))

    button.destroy()
    host.pump()
    Swag.require(host.surfaceWnd.captionButtons.isEmpty())
}

// A hidden caption action leaves the caption: the pointer reaches the strip where it stood.
#test
{
    var host: Testing.HeadlessHost
    host.setup(480, 240)
    host.surface.flags = SurfaceFlags.StandardWindow
    host.surfaceWnd.create(&host.root, null)
    host.surfaceWnd.sendResizeEvent()

    let button = CaptionButton.create(&host.surface, ThemeIcons.Settings)
    let center = button.surfaceRect().center()
    Swag.require(host.surfaceWnd.hitTestCaptionButton(center))

    button.hide()
    Swag.require(not host.surfaceWnd.hitTestCaptionButton(center))
}

// A leading action sits between the application glyph and title, remains a caption hit target,
// and leaves the native controls at the trailing edge.
#test
{
    var host: Testing.HeadlessHost
    host.setup(480, 240)
    host.surface.flags = SurfaceFlags.StandardWindow
    host.surfaceWnd.create(&host.root, null)

    let button = CaptionButton.createLeading(&host.surface, ThemeIcons.ChevronLeft)
    host.surfaceWnd.sendResizeEvent()
    let metrics = host.theme.metrics
    let client  = host.surfaceWnd.clientRect()
    Swag.require(button.position.x > client.x and button.position.x < client.horzCenter())
    Swag.require(Math.abs(button.position.vertCenter() - metrics.wnd_StripHeight * 0.5) < 0.5)
    Swag.require(host.surfaceWnd.hitTestCaptionButton(button.surfaceRect().center()))
    Swag.require(button.position.right() < host.surfaceWnd.minimizeBtn!.position.x)

    let second = CaptionButton.createLeading(&host.surface, ThemeIcons.ChevronRight)
    button.hide()
    let withoutBack = second.position.x
    button.show()
    Swag.require(second.position.x > withoutBack)
    Swag.require(button.position.right() < second.position.x)
    Swag.require(host.surfaceWnd.captionContentRect().x > second.position.right())
    second.destroy()
    host.pump()

    button.destroy()
    host.pump()
    Swag.require(host.surfaceWnd.leadingCaptionButtons.isEmpty())
}

// Room the view keeps for its own strip controls leaves the title area, at each end, and only
// there: the raw room between the leading actions and the window buttons does not move.
#test
{
    var host: Testing.HeadlessHost
    host.setup(640, 240)
    host.surface.flags = SurfaceFlags.StandardWindow
    host.surfaceWnd.create(&host.root, null)
    host.surfaceWnd.sendResizeEvent()

    let room = host.surfaceWnd.captionRoomRect()
    Swag.require(room.width > 200)
    Swag.require(host.surfaceWnd.captionContentRect() == room)

    host.surfaceWnd.reserveCaptionRoom(120, 80)
    let content = host.surfaceWnd.captionContentRect()
    Swag.require(host.surfaceWnd.captionRoomRect() == room)
    Swag.require(content.x == room.x + 120)
    Swag.require(content.right() == room.right() - 80)

    // A reservation wider than the room leaves an empty title area, never a negative one.
    host.surfaceWnd.reserveCaptionRoom(room.width, room.width)
    Swag.require(host.surfaceWnd.captionContentRect().width == 0)

    host.surfaceWnd.reserveCaptionRoom(0, 0)
    Swag.require(host.surfaceWnd.captionContentRect() == room)
}
