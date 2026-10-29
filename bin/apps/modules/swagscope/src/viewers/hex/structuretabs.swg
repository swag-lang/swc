#global internal
#global namespace Viewers.Hex

using Core, Pixel, Gui

// The strip of text tabs over the grid: the format's name in faint mono, then one tab per
// structure of the file, the one that holds the caret underlined in Arc.
//
// A tab is a place, not a mode: picking one selects the bytes of that structure in the grid.
struct StructureTabs
{
    using wnd: Wnd

    structure: *Structure?     // Borrowed from the panel that owns both.
    left:      f32             // Where the format's name starts, on the edge of the grid's offsets.
    active:    u64 = Swag.U64.Max

    // Hit areas of the tabs, as the last paint placed them.
    tabRects: Array'Math.Rectangle

    sigPicked: SigArray'func||(*StructureTabs, u64)     // Emitted with the index of the tab the reader picked.
}

private
{
    // Size of a tab's words and of the format's name, the air between two tabs, and where the Arc
    // rule stands under the words.
    const TabFontSize    = 13'u32
    const FormatFontSize = 11'u32
    const TabGap         = 24.0
    const RuleGap        = 6.0
    const RuleWidth      = 2.0
}

impl StructureTabs
{
    func create(parent: *Wnd)->*StructureTabs
    {
        with let result = Wnd.create'StructureTabs(parent, "scope.hex.tabs", {})
        {
            .backgroundStyle = .Transparent
            .dockStyle       = .Top
        }

        return result
    }

    // Shows the tabs of `structure`, or hides the strip when it names none.
    mtd setStructure(structure: *Structure)
    {
        .structure = structure
        .active    = Swag.U64.Max
        .show(not structure.tabs.isEmpty())
        .invalidate()
    }

    // Underlines the tab that holds `offset`.
    mtd follow(offset: u64)
    {
        let index = .structure ? .structure.tabAt(offset) : Swag.U64.Max
        if index == .active do
            return
        .active = index
        .invalidate()
    }
}

impl IWnd for StructureTabs
{
    mtd impl onPaint(evt: *PaintEvent)
    {
        .tabRects.clear()
        if not .structure do
            return

        let painter    = evt.paintContext.painter
        let colors     = .themeColors()
        let client     = .clientRect()
        let tabFont    = .theme().createDefaultFont(TabFontSize)
        let formatFont = .theme().createDefaultFontFs(FormatFontSize)
        let lineTop    = tabFont.opticalLineTop(client.vertCenter())

        var x = .left
        if not .structure.formatName.isEmpty()
        {
            painter.drawString(x, formatFont.opticalLineTop(client.vertCenter()), .structure.formatName, formatFont, colors.faintText)
            x += Painter.measureString(.structure.formatName, formatFont).width + TabGap
        }

        for tab, index in .structure.tabs
        {
            let width = Painter.measureString(tab.label, tabFont).width
            if x + width > client.right() do
                break

            let chosen = index == .active
            painter.drawString(x, lineTop, tab.label, tabFont, chosen ? colors.text : colors.softText)
            if chosen do
                painter.fillRect(Math.Rectangle{x, lineTop + tabFont.height + RuleGap - RuleWidth, width, RuleWidth}, colors.arc)

            .tabRects.add({x - TabGap * 0.5, client.y, width + TabGap, client.height})
            x += width + TabGap
        }
    }

    mtd impl onMouseEvent(evt: *MouseEvent)
    {
        if evt.kind != .Pressed or evt.button != .Left
        {
            evt.accepted = false
            return
        }

        let local = .surfaceToLocal(evt.surfacePos)
        for rect, index in .tabRects where rect.contains(local)
        {
            .sigPicked.call(me, index)
            return
        }

        evt.accepted = false
    }
}
