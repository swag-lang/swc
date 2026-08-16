#global public

using Core, Pixel

// Selects the weight and the meaning of a [[Gui.Separator]].
enum SeparatorForm
{
    Hairline     // Divides two groups of the same surface with a single-pixel theme line.
    Accent       // Identifies a surface or a group with a thicker accent rule.
}

// Draws a plain rule between the docked block before it and the one after it.
//
// The form carries the thickness and the color together, so a surface never repeats those
// measurements and every rule of an application agrees with the theme.
//
// A rule is the last way to separate two groups, after a raised background and after spacing:
// one per group turns a window into a grid of boxes. Reach for `Hairline` where neither works,
// and for `Accent` once, across the top edge of an application surface.
//
// ```swag
// Separator.create(mainWnd, .Top, .Accent)
// ```
struct Separator
{
    public
    {
        using wnd: Wnd     // Embedded window behavior and presentation.

        public readonly
        form = SeparatorForm.Hairline     // Weight and color of the rule.
    }
}

impl IWnd for Separator
{
    mtd impl onPaint(evt: *PaintEvent)
    {
        let painter = evt.paintContext.painter
        let colors  = .themeColors()
        let color   = .form == .Accent ? colors.hilight : colors.border

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

        painter.fillRect(rect, color)
    }
}

impl Separator
{
    // Creates a rule docked against one edge of `parent`.
    //
    // `dock` names that edge, and `form` gives the rule its thickness on the docked axis, so a
    // caller passes no measurement of its own.
    #[Swag.Discardable]
    func create(parent: *Wnd, dock: DockStyle, form = SeparatorForm.Hairline, id: #null WndId = null)->*Separator
    {
        Debug.assert(parent != null)
        Debug.assert(dock == .Top or dock == .Bottom or dock == .Left or dock == .Right, "a separator docks against one edge")

        let metrics = parent.themeMetrics()
        let size    = form == .Accent ? metrics.separator_AccentSize : metrics.separator_HairlineSize

        var position: Math.Rectangle
        if dock == .Top or dock == .Bottom do
            position.height = size
        else do
            position.width = size

        let result = Wnd.create'Separator(parent, null, position, id)
        result.form      = form
        result.dockStyle = dock
        return result
    }
}
