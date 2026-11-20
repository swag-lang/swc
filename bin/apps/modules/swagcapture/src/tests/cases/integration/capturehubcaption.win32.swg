#global if #command == Swag.CompilerCommand.Test and #os == Swag.TargetOs.Windows
#global private

using Core, Gui, Win32

// Windows recognizes the frameless capture title as a drag target.
#[Swag.TestTag("integration.capture.hub.caption")]
#test
{
    var journey: CaptureJourney
    journey.setup()
    let main = journey.main
    let app  = journey.app
    main.showHub()
    let hub     = unwrap main.residentPanel
    let surface = unwrap hub.surface
    Swag.require(surface.flags == (.SmallCaption | .CloseButton))
    let handle = surface.win32Handle()
    Swag.require(handle != null)

    var point = surface.wnd.localToSurface(surface.wnd.captionRoomRect().center())
    surface.surfaceToScreen(&point)
    let x = cast(u32, cast(s32, point.x)) & 0xFFFF
    let y = cast(u32, cast(s32, point.y)) & 0xFFFF
    let hit = Win32.SendMessageW(handle, Win32.WM_NCHITTEST, 0, cast(Win32.LPARAM, x | (y << 16)))
    const CaptionHit = 2
    Swag.require(hit == CaptionHit, "the title must allow the system to drag the capture window")
    Swag.require(not journey.surface.hasTrayIcon() and main.workspace == .Hub)

    var close = SysCommandEvent{kind: .Close}
    hub.sendEvent(&close)
    Swag.require(close.accepted)
    let frameLimit = cast(u32, app.timing.frameCount) + 15
    app.maxRunFrame = frameLimit
    Swag.require(app.run() == 0 and app.timing.frameCount < frameLimit)
    Swag.require(not journey.surface.hasTrayIcon() and main.residentPanel == null)
}
