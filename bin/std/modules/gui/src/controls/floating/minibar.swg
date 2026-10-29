#global public

using Core, Pixel

// A small floating toolbar placed next to the selected object.
//
// This is the mini-bar of the charter: the surface ground on its own small corner
// ([[Gui.ThemeMetrics.miniBar_Corner]]), [[Gui.ThemeMetrics.miniBar_Padding]] of air around
// buttons of [[Gui.ThemeMetrics.miniBar_ButtonSize]], groups parted by a short hairline. It
// carries only what applies to the selection; a `•••` button at its end opens the inspector,
// which holds the rest. Every command it offers is also an entry of the lens.
//
// The bar stays hidden until [[Gui.MiniBar.showNear]] places it beside a selection: above it when
// there is room, below it otherwise, centred on it and kept inside its parent. Move it again
// whenever the selection moves, and hide it when nothing is selected.
//
// ```swag
// with let bar = MiniBar.create(canvas)
// {
//     .addButton(theme.icon(.Copy, 16), "capture.copy", "Copy")
//     .addSeparator()
//     .addButton(theme.icon(.More, 16), "capture.inspector", "Properties")
// }
//
// bar.showNear(selectionRect)
// ```
struct MiniBar
{
    public
    {
        using wnd: Wnd     // Embedded window behavior and presentation.

        readonly
        {
            items: Array'MiniBarItem     // Items and separators, from the leading edge.
        }
    }
}

// One item of a [[Gui.MiniBar]]: a control, or the hairline between two groups.
struct MiniBarItem
{
    public
    {
        wnd: *Wnd?     // Control the bar holds, or `null` for a separator.
    }
}

impl IWnd for MiniBar
{
    mtd impl onBeforePaint(evt: *PaintEvent)
    {
        paintFloatingShadow(me, evt.paintContext.painter, .clientRect(), .themeMetrics().miniBar_Corner)
    }

    mtd impl onPaint(evt: *PaintEvent)
    {
        let painter = evt.paintContext.painter
        let metrics = .themeMetrics()
        let body    = .clientRect()
        paintFloatingGround(me, painter, body, metrics.miniBar_Corner)

        // A separator is a short hairline centred in its gap, never the full height of the bar.
        var x = metrics.miniBar_Padding
        for item, index in .items
        {
            if item.wnd
            {
                x += item.wnd.position.width
            }
            else
            {
                x += metrics.miniBar_SeparatorGap
                let top = Math.round(body.vertCenter() - metrics.miniBar_SeparatorHeight * 0.5)
                painter.fillRect(Math.Rectangle{x, top, metrics.separator_HairlineSize, metrics.miniBar_SeparatorHeight}, .themeColors().line)
                x += metrics.separator_HairlineSize + metrics.miniBar_SeparatorGap
            }

            if index + 1 < .items.count and item.wnd and .items[index + 1].wnd do
                x += metrics.miniBar_Gap
        }
    }
}

impl MiniBar
{
    // Creates an empty, hidden mini-bar over `parent`.
    #[Swag.Discardable]
    func create(parent: *Wnd, id: WndId? = null)->*MiniBar
    {
        with let result = Wnd.create'MiniBar(parent, null, {}, id)
        {
            .backgroundStyle = .Transparent
            .wndFlags.add(.Hidden)
        }

        return result
    }

    // Appends an icon button and returns it.
    //
    // The glyph is drawn at the row size of the chart; `toolTip` names the command, since the bar
    // writes no word beside a glyph.
    #[Swag.Discardable]
    mtd addButton(icon: Icon, id: WndId? = null, toolTip: string? = null, flags = IconButtonFlags.None)->*IconButton
    {
        let metrics = .themeMetrics()
        var glyph   = icon
        glyph.sizeX, glyph.sizeY = metrics.menuPopup_IconSize

        with let button = IconButton.create(me, glyph, {0, 0, metrics.miniBar_ButtonSize, metrics.miniBar_ButtonSize}, id, flags | .IconOnly)
        {
            .setForm(.RoundedRectangle)
            .setCheckIndicator(.Frame)
            .toolTip = toolTip orelse ""
        }

        .addItem(button)
        return button
    }

    // Appends a quiet text button, such as "Group", and returns it.
    #[Swag.Discardable]
    mtd addTextButton(text: string, id: WndId? = null)->*PushButton
    {
        let metrics = .themeMetrics()
        let width   = Painter.measureString(text, .theme().createDefaultFont(metrics.defaultFontSize)).width + 2 * metrics.btnPush_TextMargin
        let button  = PushButton.create(me, text, {0, 0, Math.ceil(width), metrics.miniBar_ButtonSize}, id, .Flat)
        .addItem(button)
        return button
    }

    // Appends a control the caller created, such as a colour swatch or a reading, keeping its width.
    //
    // The bar adopts `control`, gives it the height of a button and places it in the row.
    mtd addItem(control: *Wnd)
    {
        if control.parent != me do
            control.setParent(&.wnd)
        control.resize(control.position.width, .themeMetrics().miniBar_ButtonSize)
        .items.add(MiniBarItem{control})
        .arrange()
    }

    // Removes every item, destroying the controls, so the bar can be filled for another selection.
    mtd clear()
    {
        for item in .items where item.wnd do
            item.wnd.destroy()
        .items.clear()
        .arrange()
    }

    // Appends the hairline that parts two groups.
    mtd addSeparator()
    {
        .items.add(MiniBarItem{})
        .arrange()
    }

    // Returns the size of the bar; its shadow falls outside it.
    mtd bodySize()->Math.Point
    {
        let metrics = .themeMetrics()
        var width   = 2 * metrics.miniBar_Padding
        for item, index in .items
        {
            if item.wnd do
                width += item.wnd.position.width
            else do
                width += 2 * metrics.miniBar_SeparatorGap + metrics.separator_HairlineSize
            if index + 1 < .items.count and item.wnd and .items[index + 1].wnd do
                width += metrics.miniBar_Gap
        }

        return {width, metrics.miniBar_ButtonSize + 2 * metrics.miniBar_Padding}
    }

    // Shows the bar beside `selection`, a rectangle in the local coordinates of its parent.
    //
    // The bar stands [[Gui.ThemeMetrics.miniBar_Distance]] above the selection, centred on it, and
    // goes below it when the parent has no room above; with `below`, it stands below and goes
    // above when there is no room below. With room on neither side, it stands beside the
    // selection, level with its foot, on the trailing side then the leading one, and inside the
    // foot of the selection when there is no room there either. It never leaves the parent, nor
    // `room` when one is given: the part of the
    // parent that other floating surfaces, such as a dock or an inspector, leave free.
    mtd showNear(selection: Math.Rectangle, below = false, room: Math.Rectangle = {})
    {
        let parent  = unwrap .parent
        let metrics = .themeMetrics()
        let body    = .bodySize()
        var bounds  = parent.clientRect()
        if room.width > 0 and room.height > 0 do
            bounds = room
        let gap = metrics.miniBar_Distance

        var x = selection.horzCenter() - body.x * 0.5
        x = Math.clamp(x, bounds.x + gap, Math.max(bounds.x + gap, bounds.right() - gap - body.x))
        var y         = selection.y - gap - body.y
        let fitsAbove = selection.y - gap - body.y >= bounds.y + gap
        let fitsBelow = selection.bottom() + gap + body.y <= bounds.bottom() - gap
        if below
        {
            y = selection.bottom() + gap
            if not fitsBelow do
                y = selection.y - gap - body.y
        }
        elif not fitsAbove
        {
            y = selection.bottom() + gap
        }

        if not fitsAbove and not fitsBelow
        {
            y = selection.bottom() - gap - body.y
            if selection.right() + gap + body.x <= bounds.right() - gap do
                x = selection.right() + gap
            elif selection.x - gap - body.x >= bounds.x + gap do
                x = selection.x - gap - body.x
        }

        y = Math.clamp(y, bounds.y + gap, Math.max(bounds.y + gap, bounds.bottom() - gap - body.y))

        .setPosition(Math.Rectangle{Math.round(x), Math.round(y), body.x, body.y})
        .bringToFront()

        // A bar already up follows its selection; a new one leaves it, rising when it stands above.
        if .isLocallyVisible() do
            return
        let travel = .themeMetrics().motion_AnchorTravel
        discard .app().animator.arrive(me, {0, y < selection.y ? travel : -travel})
    }

    private mtd arrange()
    {
        let metrics = .themeMetrics()
        let body    = .bodySize()
        liftFloating(me)
        .resize(body.x, body.y)

        var x = metrics.miniBar_Padding
        let y = metrics.miniBar_Padding

        for item, index in .items
        {
            if item.wnd
            {
                item.wnd.move(x, y)
                x += item.wnd.position.width
            }
            else
            {
                x += 2 * metrics.miniBar_SeparatorGap + metrics.separator_HairlineSize
            }

            if index + 1 < .items.count and item.wnd and .items[index + 1].wnd do
                x += metrics.miniBar_Gap
        }

        .invalidate()
    }
}
