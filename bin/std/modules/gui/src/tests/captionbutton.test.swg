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
    Swag.assert(host.surfaceWnd.hitTestCaptionButton(center))

    button.hide()
    host.surfaceWnd.sendResizeEvent()
    Swag.assert(not host.surfaceWnd.hitTestCaptionButton(center))
}
