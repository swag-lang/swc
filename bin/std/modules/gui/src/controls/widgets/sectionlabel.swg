#global public

using Core, Pixel

// Opens a group of settings with a section label: its words in small spaced capitals, in the
// faint ink, with no rule and no band behind them.
//
// This is the label the inspector, the sheet and the lens put above a group. A surface that lays
// out its own settings, such as rows built beside a generated property grid, uses this control
// so its groups read like the ones the components draw. The label stands at the leading edge of
// the window, centred on its height; [[Gui.ThemeMetrics.inspector_SectionHeight]] is the height
// a group label takes in a column of settings.
//
// ```swag
// SectionLabel.create(column, "Color", {0, 0, 0, metrics.inspector_SectionHeight})
// ```
struct SectionLabel
{
    public
    {
        using wnd: Wnd     // Embedded window behavior and presentation.
    }

    text: String
}

impl IWnd for SectionLabel
{
    mtd impl onPaint(evt: *PaintEvent)
    {
        paintSectionLabel(me, evt.paintContext.painter, .clientRect(), .text)
    }
}

impl SectionLabel
{
    // Creates a section label naming `text` in `parent`.
    #[Swag.Discardable]
    func create(parent: *Wnd, text: string, position: Math.Rectangle = {}, id: WndId? = null)->*SectionLabel
    {
        with let result = Wnd.create'SectionLabel(parent, null, position, id)
        {
            .text            = text
            .backgroundStyle = .Transparent
        }

        return result
    }

    // Replaces the words of the label.
    mtd setText(text: string)
    {
        .text = text
        .invalidate()
    }
}
