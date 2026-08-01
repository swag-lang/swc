#global public

using Core, Pixel

// Describes one level in a [[BreadcrumbCtrl]].
struct BreadcrumbItem
{
    name:     String     // Display name.
    icon:     Icon       // Optional leading icon.
    userData: u64        // Application-defined numeric payload.
    tag:      String     // Application-defined string payload, such as a folder path.
    hasArrow = true      // Whether the level exposes a child menu.

    bodyRect:  Math.Rectangle     // Body bounds in control-local coordinates.
    arrowRect: Math.Rectangle     // Child-menu arrow bounds in control-local coordinates.
}

// Displays a horizontal path whose levels can be activated or expanded into child menus.
struct BreadcrumbCtrl
{
    using wnd: Wnd     // Embedded wnd state.

    readonly
    {
        items: Array'BreadcrumbItem     // Ordered path levels.
        padX     = 7.0'f32              // Horizontal padding inside each level body.
        iconGap  = 5.0'f32              // Gap between an icon and its label.
        arrowPad = 6.0'f32              // Padding on each side of a child-menu arrow.
    }

    sigItemPressed:  SigArray'func||(*BreadcrumbCtrl, u64)                // Emitted after a level body is activated.
    sigFillMenu:     SigArray'func||(*BreadcrumbCtrl, u64, *MenuCtrl)     // Emitted when a level's child menu needs content.
    sigMenuSelected: SigArray'func||(*BreadcrumbCtrl, u64, String)        // Emitted after a command is selected from a child menu.

    internal
    {
        hotItem   = Swag.U64.Max     // Level currently under the pointer.
        hotArrow:   bool             // Whether the pointer is over that level's arrow.
        pressItem = Swag.U64.Max     // Level on which the current press began.
        pressArrow: bool             // Whether the current press began on its arrow.
    }
}

impl BreadcrumbCtrl
{
    // Creates an empty breadcrumb control.
    #[Swag.Discardable]
    func create(parent: *Wnd, position: Math.Rectangle = {}, id: #null WndId = null)->*BreadcrumbCtrl
    {
        Debug.assert(parent != null)
        var pos = position
        if pos.height == 0 do
            pos.height = parent.themeMetrics().btnPush_Height
        let res = Wnd.create'BreadcrumbCtrl(parent, null, pos, id)
        return res
    }

    // Removes every level and clears pointer interaction state.
    mtd clear()
    {
        .items.clear()
        .hotItem    = Swag.U64.Max
        .hotArrow   = false
        .pressItem  = Swag.U64.Max
        .pressArrow = false
        .invalidate()
    }

    // Appends a level and returns its index.
    #[Swag.Discardable]
    mtd addItem(name: string, icon: Icon = {}, userData: u64 = 0, hasArrow = true, tag: #null string = null)->u64
    {
        let index = .items.count
        var it: BreadcrumbItem
        it.name     = name
        it.icon     = icon
        it.userData = userData
        it.tag      = tag
        it.hasArrow = hasArrow
        .items.add(#move it)
        .invalidate()
        return index
    }

    // Returns the level at `index`.
    mtd const itemAt(index: u64)->*BreadcrumbItem
    {
        Debug.assert(index < .items.count, "breadcrumb item index is out of range")
        return &.items[index]
    }

    // Removes `index` and every level after it.
    mtd removeItemsFrom(index: u64)
    {
        Debug.assert(index <= .items.count, "breadcrumb item index is out of range")
        while .items.count > index do
            .items.removeBack()
        .hotItem    = Swag.U64.Max
        .hotArrow   = false
        .pressItem  = Swag.U64.Max
        .pressArrow = false
        .invalidate()
    }

    // Changes body padding, icon spacing, and child-arrow padding.
    mtd setLayoutMetrics(horizontalPadding, iconSpacing, arrowPadding: f32)
    {
        Debug.assert(horizontalPadding >= 0 and iconSpacing >= 0 and arrowPadding >= 0, "layout metrics cannot be negative")
        if .padX == horizontalPadding and .iconGap == iconSpacing and .arrowPad == arrowPadding do
            return
        .padX     = horizontalPadding
        .iconGap  = iconSpacing
        .arrowPad = arrowPadding
        .invalidate()
    }

    // Recomputes per-level bounds in control-local coordinates.
    mtd layout()
    {
        let font   = nnFont(.font().regular)
        let m      = .themeMetrics()
        let client = .clientRect()

        var x = client.x
        for [i] in .items.count
        {
            let it = &.items[i]

            var w = .padX
            if it.icon.isValid() do
                w += it.icon.sizeX + .iconGap
            w += Painter.measureString(it.name.toString(), font).width + .padX

            it.bodyRect = {x, client.y, w, client.height}
            x           += w

            if it.hasArrow
            {
                let aw = .arrowPad + m.btnIcon_HeightArrow + .arrowPad
                it.arrowRect = {x, client.y, aw, client.height}
                x            += aw
            }
            else
            {
                it.arrowRect = {}
            }
        }
    }

    // Open the drop-down for the level at 'index', letting the app fill it, and report the
    // chosen entry (if any) through sigMenuSelected.
    mtd openMenu(index: u64)
    {
        if index >= .items.count do
            return

        let menu = MenuCtrl.createPopup(me)
        .sigFillMenu.call(me, index, menu)

        // Nothing to show: drop the empty popup rather than flashing an empty box.
        if menu.items.isEmpty()
        {
            menu.destroy()
            return
        }

        let ar  = .items[index].arrowRect
        let sr  = .surfaceRect()
        let sp  = Math.Point{sr.x + ar.horzCenter(), sr.y + ar.bottom()}
        let sel = menu.doModal(sp, .AnchorTopCenter, autoDestroy: true)
        if @countof(sel) != 0 do
            .sigMenuSelected.call(me, index, sel)
    }
}

impl IWnd for BreadcrumbCtrl
{
    mtd impl onMouseEvent(evt: *MouseEvent)
    {
        if evt.kind == .Leave
        {
            if .hotItem != Swag.U64.Max
            {
                .hotItem = Swag.U64.Max
                .invalidate()
            }

            return
        }

        .layout()
        let pos = .surfaceToLocal(evt.surfacePos)

        var nh      = Swag.U64.Max
        var nhArrow = false
        for [i] in .items.count
        {
            let it = &.items[i]
            if it.hasArrow and it.arrowRect.contains(pos)
            {
                nh      = i
                nhArrow = true
                break
            }

            if it.bodyRect.contains(pos)
            {
                nh = i
                break
            }
        }

        if nh != .hotItem or nhArrow != .hotArrow
        {
            .hotItem  = nh
            .hotArrow = nhArrow
            .invalidate()
        }

        // Act on a completed click (press then release over the same target), like a
        // button. Opening the chevron popup on press would start its modal loop while the
        // button is still down, and the release would dismiss it immediately.
        if evt.kind == .Pressed and evt.button == .Left
        {
            if nh != Swag.U64.Max
            {
                .pressItem  = nh
                .pressArrow = nhArrow
                .captureMouse()
            }
        }
        elif evt.kind == .Released and evt.button == .Left and .pressItem != Swag.U64.Max
        {
            let pi = .pressItem
            let pa = .pressArrow
            .pressItem = Swag.U64.Max
            .releaseMouse()

            if pi == nh and pa == nhArrow
            {
                if pa do
                    .openMenu(pi)
                else do
                    .sigItemPressed.call(me, pi)
            }
        }
    }

    mtd impl onPaint(evt: *PaintEvent)
    {
        .layout()

        let painter = evt.paintContext.painter
        let theme   = .theme()
        let colors  = .themeColors()
        let rects   = .themeRects()
        let m       = .themeMetrics()
        let font    = nnFont(.font().regular)

        painter.setParams(.Antialiased)

        for [i] in .items.count
        {
            let it      = &.items[i]
            let hotBody = i == .hotItem and !.hotArrow
            let hotArr  = i == .hotItem and .hotArrow

            // Body background + text
            if hotBody do
                painter.fillRoundRect(it.bodyRect, 4, 4, colors.btnIcon_HotBk)

            let textColor = hotBody ? colors.btnIcon_HotText : colors.btnIcon_Text
            let iconColor = hotBody ? colors.btnIcon_HotText : colors.btnIcon_Icon

            var cx = it.bodyRect.x + .padX
            if it.icon.isValid()
            {
                it.icon.paint(painter, cx, it.bodyRect.vertCenter() - it.icon.sizeY * 0.5, iconColor)
                cx += it.icon.sizeX + .iconGap
            }

            painter.drawString(cx, it.bodyRect.vertCenter() - font.height * 0.5, it.name.toString(), font, textColor)

            // Chevron (right-pointing), same orientation as the icon-button right arrow.
            if it.hasArrow
            {
                if hotArr do
                    painter.fillRoundRect(it.arrowRect, 4, 4, colors.btnIcon_HotBk)

                var posArrow: Math.Rectangle
                posArrow.width  = m.btnIcon_HeightArrow
                posArrow.height = m.btnIcon_WidthArrow
                posArrow.x      = it.arrowRect.horzCenter() - posArrow.width * 0.5
                posArrow.y      = it.arrowRect.vertCenter() - posArrow.height * 0.5
                let arrowColor = hotArr ? colors.btnIcon_HotText : colors.btnIcon_Icon
                theme.drawSubRect(painter, posArrow, &rects.btnIcon_ArrowRight, arrowColor)
            }
        }
    }
}
