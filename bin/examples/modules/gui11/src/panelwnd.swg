using Core, Gui, Pixel

const PanelPadding = 16.0
const PanelTitle   = 26.0

// A titled group the pages of this example put one idea in: a section label over its controls,
// with air rather than a box around them.
//
// Every page reaches for the same group so the four of them read as one document, and so a
// demonstration only ever has to place its own controls inside [contentRect].
struct PanelWnd
{
    using wnd: Wnd

    title: string = ""     // Heading painted along the top edge, or empty for an untitled panel.
}

impl PanelWnd
{
    func create(parent: *Wnd, title: string)->*PanelWnd
    {
        let result = Wnd.create'PanelWnd(parent, {})
        result.backgroundStyle = .Transparent
        result.title = title
        return result
    }

    // Returns the local rectangle available to the panel's children.
    mtd contentRect()->Math.Rectangle
    {
        var result: #returntype = .clientRect()
        let top = (.title).count ? PanelPadding + PanelTitle : PanelPadding
        result.applyPadding(Math.Vector4{PanelPadding, top, PanelPadding, PanelPadding})
        return result
    }
}

impl IWnd for PanelWnd
{
    mtd impl onPaint(evt: *PaintEvent)
    {
        if not (.title).count do
            return

        // The title is a section label: small spaced capitals in the faint ink.
        let painter = evt.paintContext.painter
        let metrics = .themeMetrics()
        let rect    = .clientRect()
        let font    = .theme().createDefaultFont(metrics.sectionLabel_FontSize, .Bold)
        var shaped  = Painter.shapeRun(String.toUpper(.title, .Unicode), font, letterSpacing: metrics.sectionLabel_LetterSpacing)
        painter.drawShapedRun(rect.x + PanelPadding, font.opticalLineTop(rect.y + PanelPadding + 9), &shaped, font, Brush.createSolid(.themeColors().faintText))
    }
}
