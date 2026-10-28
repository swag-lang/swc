#global public

using Core, Pixel

// A floating surface holding whatever the application puts in it.
//
// The sheet, the inspector, the mini-bar and the dock each carry a known shape of content; this
// is the ground they stand on, for a part none of them fits: a find bar over a document, the
// transport of a player floating over its picture, a list of files beside the work. It paints the
// surface ground on [[Gui.FloatingPanel.corner]] with its hairline ring and, when
// [[Gui.FloatingPanel.shadow]] is set, the floating shadow outside it; its children lay out inside
// its padding as in any window.
//
// The application places the panel, as it places any child: docked into a pane, a panel keeps the
// shape of the inspector beside the work; positioned over the work, it floats. Leave it hidden
// until it is asked for, and hide it again once it has done its job.
//
// ```swag
// with let bar = FloatingPanel.create(view, {0, 0, 420, 48})
// {
//     .padding = {8, 6, 8, 6}
// }
//
// EditBox.create(bar, "", {}).dockStyle = .Center
// ```
struct FloatingPanel
{
    public
    {
        using wnd: Wnd     // Embedded window behavior and presentation.

        corner: f32         // Corner of the ground; zero takes [[Gui.ThemeMetrics.corner_Floating]].
        shadow: bool = true // Whether the panel casts the floating shadow; a panel docked beside the work does not.
    }
}

impl IWnd for FloatingPanel
{
    mtd impl onBeforePaint(evt: *PaintEvent)
    {
        if .shadow do
            paintFloatingShadow(me, evt.paintContext.painter, .clientRect(), .radius())
    }

    mtd impl onPaint(evt: *PaintEvent)
    {
        paintFloatingGround(me, evt.paintContext.painter, .clientRect(), .radius())
    }

    mtd impl onNotifyEvent(evt: *NotifyEvent)
    {
        // The reach of the shadow follows the theme, and so does the room a repaint takes along.
        if evt.kind == .ThemeChanged do
            .lift()
        evt.accepted = false
    }
}

impl FloatingPanel
{
    // Creates a visible panel over `parent` at `position`, padded by [[Gui.ThemeMetrics.miniBar_Padding]].
    #[Swag.Discardable]
    func create(parent: *Wnd, position: Math.Rectangle = {}, id: WndId? = null)->*FloatingPanel
    {
        let pad         = parent.themeMetrics().miniBar_Padding
        with let result = Wnd.create'FloatingPanel(parent, null, position, id)
        {
            .backgroundStyle = .Transparent
            .padding         = Math.Vector4{x: pad, y: pad, z: pad, w: pad}
        }

        result.lift()
        return result
    }

    // Sets whether the panel casts the floating shadow.
    mtd setShadow(shadow: bool)
    {
        .shadow = shadow
        .lift()
        .invalidate()
    }

    // Returns the corner the ground is drawn on.
    mtd radius()->f32 => .corner > 0 ? .corner : .themeMetrics().corner_Floating

    private mtd lift()
    {
        if .shadow
        {
            liftFloating(me)
            return
        }

        .wndFlags.remove(.BeforeChildrenPaint)
        .invalidatePadding = {}
    }
}
