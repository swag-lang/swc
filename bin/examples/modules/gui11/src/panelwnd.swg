using Core, Gui, Pixel

const PanelRadius  = 10.0
const PanelPadding = 16.0
const PanelTitle   = 26.0

// A rounded, titled group box the pages of this example put one idea in.
//
// Every page reaches for the same panel so the four of them read as one document, and so a
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
        result.title           = title
        return result
    }

    // Returns the local rectangle available to the panel's children.
    mtd contentRect()->Math.Rectangle
    {
        var result: retval = .clientRect()
        let top            = @countof(.title) ? PanelPadding + PanelTitle : PanelPadding
        result.applyPadding({PanelPadding, top, PanelPadding, PanelPadding})
        return result
    }
}

impl IWnd for PanelWnd
{
    mtd impl onPaint(evt: *PaintEvent)
    {
        let painter = evt.paintContext.painter
        let colors  = .themeColors()
        let rect    = .clientRect()

        painter.fillRoundRect(rect, PanelRadius, PanelRadius, colors.wnd_Bk)
        painter.drawRoundRect(rect, PanelRadius, PanelRadius, colors.border, 1)

        if !@countof(.title) do
            return
        let font = .theme().createDefaultFont(13, .Bold)
        painter.drawString(rect.x + PanelPadding, font.opticalTop(rect.y + PanelPadding + 9, 13), .title, font, colors.label_Text)
    }
}
