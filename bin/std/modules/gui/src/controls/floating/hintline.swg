#global public

using Core, Pixel

// One key of a [[Gui.HintLine]] and what it opens.
struct HintLineItem
{
    public
    {
        key:  String     // Name of the key, written in a keycap; empty for words without a key.
        text: String     // What the key opens, in the faint ink after the keycap.
    }
}

// Teaches the door of a window: a faint line near its bottom edge, naming a key and what it opens.
//
// This is the charter's "Space — everything else": a keycap and its words in the faint ink,
// centred [[Gui.ThemeMetrics.hintLine_Bottom]] above the bottom edge of its parent. Show it while
// the reader is new to the window or the surface is empty, and hide it once the door is known. A
// faint mono reading of the work — a size, a zoom — may lead the line, as Swag Capture's does; it
// is text on the ground, not a bar.
//
// The line floats over its parent ([[Gui.DockStyle.Float]]): it takes no room from the work and
// covers only the width of what it writes.
//
// ```swag
// with let hint = HintLine.create(view)
// {
//     .setReading("880 × 550 · 100 %")
//     .addHint(strings().key_Space, "capture, open, library")
// }
// ```
struct HintLine
{
    public
    {
        using wnd: Wnd     // Embedded window behavior and presentation.

        readonly
        {
            reading: String     // Faint mono reading leading the line; empty for none.
            hints:   Array'HintLineItem     // Keys and what they open, in reading order.
        }
    }
}

impl IWnd for HintLine
{
    mtd impl onLayout()
    {
        let parent = .parent
        if not parent do
            return

        let metrics = .themeMetrics()
        let bounds  = parent.clientRect()
        let width   = Math.min(.contentWidth(), bounds.width)
        let top     = bounds.bottom() - metrics.hintLine_Bottom - metrics.hintLine_Height
        .setPosition(Math.Rectangle{Math.round(bounds.horzCenter() - width * 0.5), top, width, metrics.hintLine_Height})
    }

    mtd impl onPaint(evt: *PaintEvent)
    {
        let painter = evt.paintContext.painter
        let metrics = .themeMetrics()
        let colors  = .themeColors()
        let centerY = .clientRect().vertCenter()
        let font    = .theme().createDefaultFont(metrics.hintLine_FontSize)

        var x = 0'f32
        if not .reading.isEmpty()
        {
            x += paintTextLine(painter, x, centerY, .reading, .theme().createDefaultFontFs(metrics.hintLine_FontSize), colors.faintText)
            x += metrics.hintLine_GroupGap
        }

        for hint in .hints
        {
            if not hint.key.isEmpty()
            {
                x += paintKeycap(me, painter, x, centerY, hint.key)
                x += metrics.hintLine_KeyGap
            }

            x += paintTextLine(painter, x, centerY, hint.text, font, colors.faintText)
            x += metrics.hintLine_GroupGap
        }
    }

    mtd impl onNotifyEvent(evt: *NotifyEvent)
    {
        if evt.kind == .ThemeChanged do
            .itf.onLayout()
        evt.accepted = false
    }
}

impl HintLine
{
    // Creates an empty hint line floating over `parent`.
    #[Swag.Discardable]
    func create(parent: *Wnd, id: WndId? = null)->*HintLine
    {
        with let result = Wnd.create'HintLine(parent, null, {}, id)
        {
            .dockStyle       = .Float
            .backgroundStyle = .Transparent
        }

        return result
    }

    // Appends a key and what it opens, or with an empty `key`, words alone, such as what the tool
    // in hand does.
    mtd addHint(key: string, text: string)
    {
        .hints.add(HintLineItem{key, text})
        .relayout()
    }

    // Removes every hint, keeping the reading.
    mtd clearHints()
    {
        .hints.clear()
        .relayout()
    }

    // Sets the faint mono reading that leads the line, or removes it with `null`.
    mtd setReading(reading: string?)
    {
        .reading = reading orelse ""
        .relayout()
    }

    // Returns the width of everything the line writes.
    mtd contentWidth()->f32
    {
        let metrics = .themeMetrics()
        let font    = .theme().createDefaultFont(metrics.hintLine_FontSize)

        var result = 0'f32
        if not .reading.isEmpty() do
            result += Painter.measureString(.reading, .theme().createDefaultFontFs(metrics.hintLine_FontSize)).width + metrics.hintLine_GroupGap
        for hint in .hints
        {
            if not hint.key.isEmpty() do
                result += keycapWidth(me, hint.key) + metrics.hintLine_KeyGap
            result += Painter.measureString(hint.text, font).width + metrics.hintLine_GroupGap
        }

        if result > 0 do
            result -= metrics.hintLine_GroupGap
        return Math.ceil(result)
    }

    private mtd relayout()
    {
        .itf.onLayout()
        .invalidate()
    }
}
