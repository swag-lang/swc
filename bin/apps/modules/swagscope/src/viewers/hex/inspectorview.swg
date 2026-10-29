#global internal
#global namespace Viewers.Hex

using Core, Pixel, Gui

// One line of the inspector: what is read, and its value at the right.
struct InspectorLine
{
    label:  String
    value:  String
    strong: bool     // Whether this is the field the caret stands on.
}

// What the floating inspector shows of the byte under the caret: its value in large type over
// what it was read as, the same bytes in the other common readings, then the fields of the
// structure that holds it.
struct InspectorView
{
    using wnd: Wnd

    headline: String
    caption:  String
    readings: Array'InspectorLine
    fields:   Array'InspectorLine
}

private
{
    // Air inside the card, the pitch of a line, the size of the value, and the air around the
    // hairline that separates the readings from the fields.
    const CardInset    = 24.0
    const LinePitch    = 25.0
    const HeadlineSize = 28'u32
    const LabelSize    = 13'u32
    const ValueSize    = 12'u32
    const CaptionSize  = 11'u32
    const HeadlineGap  = 22.0
    const SeparatorAir = 16.0
}

impl InspectorView
{
    func create(parent: *Wnd)->*InspectorView
    {
        with let result = Wnd.create'InspectorView(parent, "scope.hex.inspector.view", {})
        {
            .backgroundStyle = .Transparent
            .dockStyle       = .Center
        }

        return result
    }

    // Returns the height the card needs for what it shows now.
    mtd contentHeight()->f32
    {
        let headline = .theme().createDefaultFont(HeadlineSize)
        let caption  = .theme().createDefaultFontFs(CaptionSize)
        var result   = CardInset + headline.height + caption.height + HeadlineGap - LinePitch * 0.25
        result += cast(f32, .readings.count) * LinePitch
        if not .fields.isEmpty() do
            result += 2 * SeparatorAir + cast(f32, .fields.count) * LinePitch

        // A line keeps air under its words, so the last one already gives part of the inset.
        return result + CardInset - LinePitch * 0.25
    }

    // Draws `lines` from `top`, one per pitch, labels at the left and values at the right.
    private mtd paintLines(painter: *Painter, lines: const *Array'InspectorLine, top: f32)
    {
        let colors = .themeColors()
        let client = .clientRect()
        let left   = client.x + CardInset
        let right  = client.right() - CardInset
        let label  = .theme().createDefaultFont(LabelSize)
        let value  = .theme().createDefaultFontFs(ValueSize)
        let strong = .theme().createDefaultFontFs(ValueSize, .Bold)

        var y = top
        for line in lines
        {
            let center    = y + LinePitch * 0.5
            let valueFont = line.strong ? strong : value
            let width     = Painter.measureString(line.value, valueFont).width
            painter.drawString(left, label.opticalLineTop(center), line.label, label, colors.softText)
            painter.drawString(right - width, valueFont.opticalLineTop(center), line.value, valueFont, line.strong ? colors.text : colors.softText)
            y += LinePitch
        }
    }
}

impl IWnd for InspectorView
{
    mtd impl onPaint(evt: *PaintEvent)
    {
        let painter = evt.paintContext.painter
        let colors  = .themeColors()
        let client  = .clientRect()
        let left    = client.x + CardInset

        let headline = .theme().createDefaultFont(HeadlineSize)
        let caption  = .theme().createDefaultFontFs(CaptionSize)
        var y        = client.y + CardInset
        painter.drawString(left, y, .headline, headline, colors.text)
        y += headline.height
        painter.drawString(left, y, .caption, caption, colors.faintText)
        y += caption.height + HeadlineGap - LinePitch * 0.25

        .paintLines(painter, &.readings, y)
        y += cast(f32, .readings.count) * LinePitch
        if .fields.isEmpty() do
            return

        y += SeparatorAir
        painter.drawLine(left, y, client.right() - CardInset, y, colors.line, 1)
        y += SeparatorAir
        .paintLines(painter, &.fields, y)
    }
}
