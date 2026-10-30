#global if #os == Swag.TargetOs.Windows
#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Win32

struct StartupProbeWnd
{
    using wnd:         Wnd
    maximize:          bool
    initializing:      bool
    paints:            u32
    initializations:   u32
    shows:             u32
    paintsDuringInit:  u32
    visibleDuringInit: bool
    firstPaintVisible: bool
    showsWithoutFrame: bool
    showsWhileHidden:  bool
}

impl IWnd for StartupProbeWnd
{
    mtd impl onStateEvent(evt: *StateEvent)
    {
        let surface = unwrap .surface
        if evt.kind == .Init
        {
            .initializations += 1
            .initializing    = true
            surface.setPosition({60, 50, 420, 260})
            surface.showNormalAt({70, 60, 480, 300})
            if .maximize do
                surface.showMaximized()
            .visibleDuringInit = IsWindowVisible(surface.win32Handle()) != 0
            .initializing      = false
            evt.accepted       = true
        }
        elif evt.kind == .Show
        {
            .shows             += 1
            .showsWithoutFrame = .showsWithoutFrame or .paints == 0
            .showsWhileHidden  = .showsWhileHidden or not IsWindowVisible(surface.win32Handle())
            evt.accepted       = true
        }
    }

    mtd impl onPaint(_: *PaintEvent)
    {
        if .initializing do
            .paintsDuringInit += 1
        if .paints == 0 do
            .firstPaintVisible = IsWindowVisible(.surface!.win32Handle()) != 0
        .paints += 1
    }
}

// Restoring several placements during Init prepares only the final content, including when
// maximized. Hiding and showing again keeps the one-time initialization contract.
#[Swag.TestTag("integration.host.windows")]
#test
{
    for maximize in [false, true]
    {
        var app: Application
        let surface = expect app.createSurface(40, 40, 320, 180, .StandardWindow, surfaceId: "gui-startup-placement-test")
        let view    = Wnd.create'StartupProbeWnd(surface.wnd)
        surface.setView(view)
        view.maximize = maximize
        surface.show()
        Swag.assert(view.initializations == 1 and view.shows == 1)
        Swag.assert(view.paintsDuringInit == 0, "initial placement must not paint an intermediate frame")
        Swag.assert(not view.visibleDuringInit, "initial placement must keep the native window hidden")
        Swag.assert(not view.firstPaintVisible, "the first complete frame must precede visibility")
        Swag.assert(not view.showsWithoutFrame and not view.showsWhileHidden)
        Swag.assert(surface.isMaximized == maximize)
        var placement: WINDOWPLACEMENT
        placement.length = #sizeof(placement)
        Swag.assert(GetWindowPlacement(surface.win32Handle(), &placement))
        Swag.assert(placement.showCmd == (maximize ? SW_SHOWMAXIMIZED : SW_SHOWNORMAL))
        var client: RECT
        Swag.assert(GetClientRect(surface.win32Handle(), &client))
        Swag.assert(surface.rc.width == client.right and surface.rc.height == client.bottom)
        // Activation may invalidate focus decoration after the first complete frame.
        Swag.assert(surface.rt.colorBuffer.width >= client.right and surface.rt.colorBuffer.height >= client.bottom)
        surface.hide()
        surface.show()
        Swag.assert(view.initializations == 1 and view.shows == 2)
        Swag.assert(GetWindowPlacement(surface.win32Handle(), &placement))
        Swag.assert(placement.showCmd == (maximize ? SW_SHOWMAXIMIZED : SW_SHOWNORMAL))
        surface.showNormal()
        Swag.assert(surface.position == Math.Rectangle{70, 60, 480, 300})
    }
}
