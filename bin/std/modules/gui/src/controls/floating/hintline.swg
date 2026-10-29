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

// Where a [[Gui.HintLine]] stands along the bottom edge of its parent.
enum HintLineAlignment
{
    Center       // Centred on the parent.
    Leading      // From the leading edge of the parent's padded rectangle.
    Trailing     // Up to the trailing edge of the parent's padded rectangle.
}

// Teaches the door of a window: a faint line near its bottom edge, naming a key and what it opens.
//
// This is the charter's "Ctrl Space — everything else": a keycap and its words in the faint ink,
// centred [[Gui.ThemeMetrics.hintLine_Bottom]] above the bottom edge of its parent. Show it while
// the reader is new to the window or the surface is empty, and hide it once the door is known. A
// faint mono reading of the work — a size, a zoom — may lead the line, as Swag Capture's does; it
// is text on the ground, not a bar.
//
// The line floats over its parent ([[Gui.DockStyle.Float]]): it takes no room from the work and
// covers only the width of what it writes. A window whose work stands in columns can set a line at
// either side of its page instead, on the edges the parent's padding measures: a leading line
// teaching the keys under the first column, a trailing one reading the work under the last.
//
// ```swag
// with let hint = HintLine.create(view)
// {
//     .setReading("880 × 550 · 100 %")
//     .addHint(Input.formatKeyShortcut(.Control, .Space), "capture, open, library")
// }
// ```
struct HintLine
{
    public
    {
        using wnd: Wnd     // Embedded window behavior and presentation.

        readonly
        {
            reading:   String                 // Faint mono reading leading the line; empty for none.
            hints:     Array'HintLineItem     // Keys and what they open, in reading order.
            alignment: HintLineAlignment      // Where the line stands along the bottom edge.
            grounded:  bool                   // Whether the line stands on the floating ground, over a busy picture.
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

        // The margin of the line keeps it clear of what floats along the sides of its parent,
        // such as a dock or an inspector: it centres in the room left between them.
        let metrics = .themeMetrics()
        var bounds  = parent.clientRect()
        bounds.x     += .margin.x
        bounds.width = Math.max(bounds.width - .margin.x - .margin.z, 0)
        let page   = parent.paddedClientRect()
        let pad    = .groundPadding()
        let height = metrics.hintLine_Height + 2 * pad.y
        let top    = bounds.bottom() - metrics.hintLine_Bottom - metrics.hintLine_Height - pad.y
        switch #complete .alignment
        {
        case .Center:
            let width = Math.min(.fit(bounds.width - 2 * pad.x).width + 2 * pad.x, bounds.width)
            .setPosition(Math.Rectangle{Math.round(bounds.horzCenter() - width * 0.5), top, width, height})

        case .Leading:
            let width = Math.min(.fit(page.width - 2 * pad.x).width + 2 * pad.x, page.width)
            .setPosition(Math.Rectangle{page.x, top, width, height})

        case .Trailing:
            let width = Math.min(.fit(page.width - 2 * pad.x).width + 2 * pad.x, page.width)
            .setPosition(Math.Rectangle{page.right() - width, top, width, height})
        }
    }

    mtd impl onPaint(evt: *PaintEvent)
    {
        let painter = evt.paintContext.painter
        let metrics = .themeMetrics()
        let colors  = .themeColors()
        let centerY = .clientRect().vertCenter()
        let font    = .theme().createDefaultFont(metrics.hintLine_FontSize)

        // Over a busy picture the words stand on the floating ground, in the secondary ink.
        var ink = colors.faintText
        if .grounded
        {
            paintFloatingGround(me, painter, .clientRect(), metrics.corner_Control)
            ink = colors.softText
        }

        var x = .groundPadding().x
        if not .reading.isEmpty()
        {
            x += paintTextLine(painter, x, centerY, .reading, .theme().createDefaultFontFs(metrics.hintLine_FontSize), ink)
            x += metrics.hintLine_GroupGap
        }

        // The hints that do not fit are left out whole, rather than cut in the middle of a word.
        let shown = .fit(.clientRect().width - 2 * .groundPadding().x + 1).count
        for hint, i in .hints where i < shown
        {
            if not hint.key.isEmpty()
            {
                x += paintKeycap(me, painter, x, centerY, hint.key)
                x += metrics.hintLine_KeyGap
            }

            x += paintTextLine(painter, x, centerY, hint.text, font, ink)
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

    // Stands the line on the floating ground, for a line over a busy picture such as a frozen
    // screen, where words on the bare picture cannot be read.
    mtd setGrounded(grounded: bool)
    {
        .grounded = grounded
        .relayout()
    }

    // Stands the line at `alignment` along the bottom edge of its parent.
    mtd setAlignment(alignment: HintLineAlignment)
    {
        .alignment = alignment
        .relayout()
    }

    // Returns the width of everything the line writes.
    mtd contentWidth()->f32 => .fit(Swag.F32.Max).width

    // Returns how many hints fit in `limit` after the reading, which always stands, and the width
    // the reading and those hints take.
    private mtd fit(limit: f32)->{ count: u64, width: f32 }
    {
        let metrics = .themeMetrics()
        let font    = .theme().createDefaultFont(metrics.hintLine_FontSize)

        var width = 0'f32
        if not .reading.isEmpty() do
            width = Painter.measureString(.reading, .theme().createDefaultFontFs(metrics.hintLine_FontSize)).width

        var count = 0'u64
        for hint in .hints
        {
            var next = width > 0 ? metrics.hintLine_GroupGap : 0
            if not hint.key.isEmpty() do
                next += keycapWidth(me, hint.key) + metrics.hintLine_KeyGap
            next += Painter.measureString(hint.text, font).width
            if width + next > limit do
                break
            width += next
            count += 1
        }

        return {count, Math.ceil(width)}
    }

    // The air between the floating ground and the words, nothing when the line has no ground.
    private mtd groundPadding()->Math.Point
    {
        if not .grounded do
            return {}
        let metrics = .themeMetrics()
        return {metrics.hintLine_KeyGap * 2, metrics.miniBar_Padding}
    }

    private mtd relayout()
    {
        .itf.onLayout()
        .invalidate()
    }
}
