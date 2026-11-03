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
    Swag.assert(host.surfaceWnd.captionButtons.count == 1)
    Swag.assert(button.parent == &host.surfaceWnd)
    Swag.assert(button.icon.index == cast(s32, ThemeIcons.Settings))

    button.destroy()
    host.pump()
    Swag.assert(host.surfaceWnd.captionButtons.isEmpty())
}
#test
{
    var host: Testing.HeadlessHost
    host.setup(480, 240)
    host.surface.flags = SurfaceFlags.StandardWindow
    host.surfaceWnd.create(&host.root, null)
    host.surfaceWnd.sendResizeEvent()

    let button = CaptionButton.create(&host.surface, ThemeIcons.Settings)
    let center = button.surfaceRect().center()
    Swag.assert(host.surfaceWnd.hitTestCaptionButton(center))

    button.hide()
    Swag.assert(not host.surfaceWnd.hitTestCaptionButton(center))
}
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
    Swag.assert(button.position.x > client.x and button.position.x < client.horzCenter())
    Swag.assert(Math.abs(button.position.vertCenter() - metrics.wnd_StripHeight * 0.5) < 0.5)
    Swag.assert(host.surfaceWnd.hitTestCaptionButton(button.surfaceRect().center()))
    Swag.assert(button.position.right() < host.surfaceWnd.minimizeBtn!.position.x)

    let second = CaptionButton.createLeading(&host.surface, ThemeIcons.ChevronRight)
    button.hide()
    let withoutBack = second.position.x
    button.show()
    Swag.assert(second.position.x > withoutBack)
    Swag.assert(button.position.right() < second.position.x)
    Swag.assert(host.surfaceWnd.captionContentRect().x > second.position.right())
    second.destroy()
    host.pump()

    button.destroy()
    host.pump()
    Swag.assert(host.surfaceWnd.leadingCaptionButtons.isEmpty())
}
