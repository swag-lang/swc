#global public

using Core, Pixel

// Draws a hairline between the docked block before it and the one after it.
//
// The rule takes its thickness and its color from the theme, so a surface never repeats those
// measurements and every rule of an application agrees with the theme.
//
// A rule is the last way to separate two groups, after spacing and after a raised background:
// one per group turns a window into a grid of boxes. Reach for it only where neither works. There
// is no heavier form: a window carries no accent rail.
//
// ```swag
// Separator.create(panel, .Bottom)
// ```
struct Separator
{
    public
    {
        using wnd: Wnd     // Embedded window behavior and presentation.
    }
}

impl IWnd for Separator
{
    mtd impl onPaint(evt: *PaintEvent)
    {
        let painter = evt.paintContext.painter

        // A rule must cover whole device pixels: snap the edges of its thin axis so
        // a one-unit hairline never straddles two half-covered pixel rows.
        var rect = .clientRect()
        if rect.height <= rect.width
        {
            let y = painter.snapToDeviceY(rect.y)
            rect.height = Math.max(painter.hairline(rect.height), painter.snapToDeviceY(rect.bottom()) - y)
            rect.y      = y
        }
        else
        {
            let x = painter.snapToDeviceX(rect.x)
            rect.width = Math.max(painter.hairline(rect.width), painter.snapToDeviceX(rect.right()) - x)
            rect.x     = x
        }

        painter.fillRect(rect, .themeColors().line)
    }
}

impl Separator
{
    // Creates a hairline docked against one edge of `parent`.
    //
    // `dock` names that edge, and the theme gives the rule its thickness on the docked axis, so a
    // caller passes no measurement of its own.
    #[Swag.Discardable]
    func create(parent: *Wnd, dock: DockStyle, id: WndId? = null)->*Separator
    {
        Swag.assert(parent != null)
        Swag.assert(dock == .Top or dock == .Bottom or dock == .Left or dock == .Right, "a separator docks against one edge")

        let size = parent.themeMetrics().separator_HairlineSize
        var position: Math.Rectangle
        if dock == .Top or dock == .Bottom do
            position.height = size
        else do
            position.width = size

        let result = Wnd.create'Separator(parent, null, position, id)
        result.dockStyle = dock
        return result
    }
}
