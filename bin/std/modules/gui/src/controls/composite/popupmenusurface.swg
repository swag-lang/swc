#global public

using Core, Pixel

// Selects where a detached popup menu stands relative to its physical screen anchor.
enum PopupMenuSurfacePlacement
{
    AtPoint        // Opens at the anchor point and stays within its monitor's work area.
    BelowAnchor    // Opens below the anchor rectangle, or above it when it does not fit.
}

// Opens a [[Gui.MenuCtrl]] on its own native surface, outside the bounds of its caller.
//
// The caller owns its menu items and selection command. This helper owns the common surface
// creation, size, placement, focus handoff and focus-loss watch used by detached menus.
struct PopupMenuSurface {}

impl PopupMenuSurface
{
    // Creates a tool surface at `anchor` so its initial DPI matches that monitor.
    // Returns `null` when the native surface could not be created.
    #[Swag.Discardable]
    func create(app: *Application, anchor: Math.Point)->*Surface?
    {
        let surface = catch app.createSurface(cast(s32, anchor.x), cast(s32, anchor.y),
                                              300, 300, .ToolWindow | .TopMost)
        {
            return null
        }
        surface.minSize = {}
        return surface
    }

    // Shows `view` and its measured `menu` on the separate surface at a physical screen anchor.
    //
    // `monitorPoint` selects the work area used for clamping. `anchor` and `monitorPoint` are
    // physical screen coordinates; the menu and its shadow are measured in logical units.
    func show(view: *Wnd, menu: *MenuCtrl, anchor: Math.Rectangle,
             placement: PopupMenuSurfacePlacement, monitorPoint: Math.Point)
    {
        let surface = unwrap view.surface
        menu.updateState()
        menu.computeLayoutPopup()

        let shadow = surface.shadowMargin()
        let scale  = surface.dpiScale
        let width  = Math.ceil((menu.position.width + 2 * shadow) * scale)
        let height = Math.ceil((menu.position.height + 2 * shadow) * scale)
        let work   = Env.monitorForPoint(monitorPoint).physicalWorkArea
        let x      = Math.clamp(anchor.x, work.x, Math.max(work.x, work.right() - width))
        var y      = placement == .BelowAnchor ? anchor.bottom() : anchor.y
        if placement == .BelowAnchor and y + height > work.bottom() do
            y = anchor.y - height
        y = Math.clamp(y, work.y, Math.max(work.y, work.bottom() - height))

        surface.setView(view)
        surface.setPosition({x, y, width, height})
        surface.show()
        surface.bringToFront()
        #static if #os == Swag.TargetOs.Windows
        {
            // A tray icon still owns foreground while its callback is being dispatched.
            if surface.win32Handle() do
                discard Win32.SetForegroundWindow(surface.win32Handle())
        }
        view.setFocus()
    }

    // Returns true when a detached menu has a choice or lost desktop focus.
    //
    // Call from a short repeating timer. The first poll arms pointer routing after the opening
    // gesture finishes; the two Boolean fields belong to that one popup instance.
    func shouldDismiss(view: *Wnd, menu: *MenuCtrl, wasActive, armed: *bool)->bool
    {
        if menu.isModalEnded() do
            return true
        if not armed[]
        {
            menu.captureMouse()
            armed[] = true
        }
        if view.app().isActivated
        {
            wasActive[] = true
            return false
        }
        return wasActive[]
    }
}
