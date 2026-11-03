#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

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
