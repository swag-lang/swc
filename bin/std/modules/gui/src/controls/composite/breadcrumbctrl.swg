#global public

using Core, Pixel

// Describes one level in a [[Gui.BreadcrumbCtrl]].
struct BreadcrumbItem
{
    public
    {
        name:     String     // Display name.
        icon:     Icon       // Optional leading icon.
        userData: u64        // Application-defined numeric payload.
        tag:      String     // Application-defined string payload, such as a folder path.
        hasArrow = true      // Whether the level exposes a child menu.

        bodyRect:  Math.Rectangle     // Body bounds in control-local coordinates.
        arrowRect: Math.Rectangle     // Child-menu arrow bounds in control-local coordinates.
    }
}

// The mark parting two levels of a quiet path.
private const QuietSeparator = "/"

// Displays a horizontal path whose levels can be activated or expanded into child menus.
struct BreadcrumbCtrl
{
    public
    {
        using wnd: Wnd     // Embedded window behavior and presentation.

        iconSize:   f32 = 16     // Square size used for every level icon; zero uses each descriptor's own size.
        quiet:      bool         // Whether the path reads as a page names its place: faint words parted by slashes, a slash still opening its menu.
        fitToWidth: bool         // Keeps complete trailing levels in view and gathers hidden ancestors in an overflow menu.

        readonly
        {
            items: Array'BreadcrumbItem     // Ordered path levels.
            padX     = 7.0'f32     // Horizontal padding inside each level body.
            iconGap  = 5.0'f32     // Gap between an icon and its label.
            arrowPad = 6.0'f32     // Padding on each side of a child-menu arrow.
        }

        sigItemPressed:  SigArray'func||(*Wnd, u64)                // Emitted after a level body is activated.
        sigFillMenu:     SigArray'func||(*Wnd, u64, *MenuCtrl)     // Emitted when a level's child menu needs content.
        sigMenuSelected: SigArray'func||(*Wnd, u64, String)        // Emitted after a command is selected from a child menu.

        // Emitted after a click on the part of the control no level covers, which is where an
        // address bar offers to type the path instead.
        sigEmptyPressed: SigArray'func||(*Wnd)
    }

    hotItem   = Swag.U64.Max          // Level currently under the pointer.
    hotArrow:      bool               // Whether the pointer is over that level's arrow.
    pressItem = Swag.U64.Max          // Level on which the current press began.
    pressArrow:    bool               // Whether the current press began on its arrow.
    pressEmpty:    bool               // Whether the current press began where no level is.
    overflowRect:  Math.Rectangle     // Overflow trigger when ancestors do not fit.
    firstVisible:  u64                // First level after the overflow trigger.
    hotOverflow:   bool
    pressOverflow: bool
    ancestorIcon:  Icon     // Fallback for a path bar's hidden ancestor rows.
}

impl BreadcrumbCtrl
{
    // Creates an empty breadcrumb control.
    #[Swag.Discardable]
    func create(parent: *Wnd, position: Math.Rectangle = {}, id: WndId? = null)->*BreadcrumbCtrl
    {
        Swag.assert(parent != null)
        var pos = position
        if pos.height == 0 do
            pos.height = parent.themeMetrics().btnPush_Height
        let res = Wnd.create'BreadcrumbCtrl(parent, null, pos, id)
        res.focusPolicy = .Click
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
        .pressEmpty = false
        .hotOverflow, .pressOverflow = false
        .invalidate()
    }

    // Appends a level and returns its index.
    #[Swag.Discardable]
    mtd addItem(name: string, icon: Icon = {}, userData: u64 = 0, hasArrow = true, tag: string? = null)->u64
    {
        let index = .items.count
        with var it: BreadcrumbItem
        {
            .name     = name
            .icon     = icon
            .userData = userData
            .tag      = tag
            .hasArrow = hasArrow
        }

        .items.add(#move it)
        .invalidate()
        .invalidateLayout()
        return index
    }

    // Returns the level at `index`.
    mtd const itemAt(index: u64)->*BreadcrumbItem
    {
        Swag.assert(index < .items.count, "breadcrumb item index is out of range")
        return &.items[index]
    }

    // Removes `index` and every level after it.
    mtd removeItemsFrom(index: u64)
    {
        Swag.assert(index <= .items.count, "breadcrumb item index is out of range")
        while .items.count > index do
            .items.removeBack()
        .hotItem    = Swag.U64.Max
        .hotArrow   = false
        .pressItem  = Swag.U64.Max
        .pressArrow = false
        .pressEmpty = false
        .hotOverflow, .pressOverflow = false
        .invalidate()
        .invalidateLayout()
    }

    // Changes body padding, icon spacing, and child-arrow padding.
    mtd setLayoutMetrics(horizontalPadding, iconSpacing, arrowPadding: f32)
    {
        Swag.assert(horizontalPadding >= 0 and iconSpacing >= 0 and arrowPadding >= 0, "layout metrics cannot be negative")
        if .padX == horizontalPadding and .iconGap == iconSpacing and .arrowPad == arrowPadding do
            return
        .padX     = horizontalPadding
        .iconGap  = iconSpacing
        .arrowPad = arrowPadding
        .invalidate()
        .invalidateLayout()
    }

    // Recomputes per-level bounds in control-local coordinates.
    mtd layout()
    {
        let client = .clientRect()

        var x = client.x
        for &it in .items
        {
            let w = .bodyWidth(it)
            it.bodyRect = Math.Rectangle{x, client.y, w, client.height}
            x += w

            if it.hasArrow
            {
                let aw = .arrowWidth()
                it.arrowRect = Math.Rectangle{x, client.y, aw, client.height}
                x += aw
            }
            else
            {
                it.arrowRect = {}
            }
        }

        .overflowRect = {}
        .firstVisible = 0
        if not .fitToWidth or .items.isEmpty() or x <= client.right() do
            return

        // Keep whole ancestors, never the trailing letters of one. The leaf always stays.
        let overflowWidth = Math.min(.themeMetrics().control_DialogHeight, client.width)
        let available     = Math.max(client.width - overflowWidth, 0)
        .firstVisible = .items.count - 1
        var used = .items.back().bodyRect.width + .items.back().arrowRect.width
        while .firstVisible > 0
        {
            let previous = .items[.firstVisible - 1]
            let width    = previous.bodyRect.width + previous.arrowRect.width
            if used + width > available do
                break
            used += width
            .firstVisible -= 1
        }

        .overflowRect = {client.x, client.y, .firstVisible > 0 ? overflowWidth : 0, client.height}
        x = .overflowRect.right()
        for &it, index in .items
        {
            if index < .firstVisible
            {
                it.bodyRect  = {}
                it.arrowRect = {}
                continue
            }

            let arrowWidth = Math.min(it.arrowRect.width, Math.max(client.right() - x, 0))
            it.bodyRect.x      = x
            it.bodyRect.width  = Math.min(it.bodyRect.width, Math.max(client.right() - x - arrowWidth, 0))
            x                  = it.bodyRect.right()
            it.arrowRect.x     = x
            it.arrowRect.width = arrowWidth
            x                  += arrowWidth
        }
    }

    // Returns the width of the body of `item`: its icon, its name, and their padding.
    private mtd bodyWidth(item: const *BreadcrumbItem)->f32
    {
        var width = .padX
        if item.icon.isValid() do
            width += (.iconSize != 0 ? .iconSize : item.icon.sizeX) + .iconGap
        let font = nnFont(.font().regular)
        return width + Math.ceil(Painter.measureStringSnapped(item.name, font, deviceScale: .deviceScale())) + .padX
    }

    // Returns the width of the mark opening the child menu of a level, with its padding.
    private mtd arrowWidth()->f32
    {
        let mark = .quiet ? Painter.measureString(QuietSeparator, nnFont(.font().regular)).width : .themeMetrics().chevron_Size
        return .arrowPad + mark + .arrowPad
    }

    // Opens the child menu of the level at `index` and reports the command chosen in it.
    //
    // [[Gui.BreadcrumbCtrl.sigFillMenu]] fills the menu first; an empty menu is not shown. A chosen
    // command is emitted through [[Gui.BreadcrumbCtrl.sigMenuSelected]].
    mtd openMenu(index: u64)
    {
        if index >= .items.count do
            return

        .layout()
        let menu = MenuCtrl.createPopup(me)
        defer menu.destroy()
        .sigFillMenu.call(me, index, menu)

        // Nothing to show: drop the empty popup rather than flashing an empty box.
        if menu.items.isEmpty() do
            return

        var rect = .items[index].bodyRect
        rect.width += .items[index].arrowRect.width
        let sel = .showLevelMenu(menu, rect, .items[index].name)
        if sel.count != 0 do
            .sigMenuSelected.call(me, index, sel)
    }
}

private impl BreadcrumbCtrl
{
    // Use the same attached tab as other menu buttons, aligned with the complete level.
    mtd showLevelMenu(menu: *MenuCtrl, rect: Math.Rectangle, name: string, overflow = false)->String
    {
        let anchor = IconButton.createQuiet(me, menu: not overflow)
        defer anchor.destroy()
        anchor.style.setFont(.font())
        let arrowRoom = overflow ? 0.0 : .themeMetrics().btnIcon_ArrowSize + .themeMetrics().btnIcon_SpacingTextH
        let room      = Math.max(rect.width - .padX * 2 - arrowRoom, 0)
        anchor.setQuietText(Painter.elideString(name, nnFont(.font().regular), room, .deviceScale()))
        anchor.setPosition({rect.x - .scrollPos.x, rect.y - .scrollPos.y, rect.width, rect.height})
        return String.from(menu.doModal(anchor) orelse "")
    }

    mtd openAncestors()
    {
        let menu = MenuCtrl.createPopup(me)
        defer menu.destroy()
        for index in 0 until .firstVisible
        {
            let item = &.items[index]
            menu.addItem(item.name, Format.toString("%", index), item.icon.isValid() ? item.icon : .ancestorIcon)
        }

        var rect     = .overflowRect
        let selected = .showLevelMenu(menu, rect, "…", overflow: true)
        if selected.count do
            .sigItemPressed.call(me, (expect StrConv.parseU64(selected)).value)
    }
}

impl IWnd for BreadcrumbCtrl
{
    // Reports the width every level takes when none is gathered into the overflow menu, so a host
    // can share a line between the path and its neighbours before it fits the path to its room.
    mtd impl measureContent(_: Math.Point)->Math.Point
    {
        var width: f32
        for &it in .items
        {
            width += .bodyWidth(it)
            if it.hasArrow do
                width += .arrowWidth()
        }

        return {width, 0}
    }

    mtd impl onMouseEvent(evt: *MouseEvent)
    {
        if evt.kind == .Leave
        {
            if .hotItem != Swag.U64.Max or .hotOverflow
            {
                .hotItem     = Swag.U64.Max
                .hotOverflow = false
                .invalidate()
            }

            return
        }

        .layout()
        let pos = .surfaceToLocal(evt.surfacePos) + .scrollPos

        var nh      = Swag.U64.Max
        var nhArrow = false
        for it, i in .items where not it.bodyRect.isEmpty()
        {
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

        let overflow = not .overflowRect.isEmpty() and .overflowRect.contains(pos)
        if nh != .hotItem or nhArrow != .hotArrow or overflow != .hotOverflow
        {
            .hotItem     = nh
            .hotArrow    = nhArrow
            .hotOverflow = overflow
            .invalidate()
        }

        // Act on a completed click (press then release over the same target), like a
        // button. Opening the chevron popup on press would start its modal loop while the
        // button is still down, and the release would dismiss it immediately.
        let empty = nh == Swag.U64.Max and not overflow and .clientRect().contains(pos - .scrollPos)
        if evt.kind == .Pressed and evt.button == .Left
        {
            if nh != Swag.U64.Max or empty or overflow
            {
                .pressItem     = nh
                .pressArrow    = nhArrow
                .pressEmpty    = empty
                .pressOverflow = overflow
                .captureMouse()
            }
        }
        elif evt.kind == .Released and
             evt.button == .Left and
             (.pressItem != Swag.U64.Max or .pressEmpty or .pressOverflow)
        {
            let pi = .pressItem
            let pa = .pressArrow
            let pe = .pressEmpty
            let po = .pressOverflow
            .pressItem     = Swag.U64.Max
            .pressEmpty    = false
            .pressOverflow = false
            .releaseMouse()

            if po
            {
                if overflow do
                    .openAncestors()
            }
            elif pe
            {
                if empty do
                    .sigEmptyPressed.call(me)
            }
            elif pi == nh and pa == nhArrow
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
        let m       = .themeMetrics()
        let font    = nnFont(.font().regular)

        painter.setParams(.Antialiased)

        if not .overflowRect.isEmpty()
        {
            if .hotOverflow do
                painter.fillRoundRect(.overflowRect, m.corner_Control, m.corner_Control, colors.btnIcon_HotBk)
            let mark = theme.icon(.More, m.fileBrowser_GlyphSize)
            mark.paint(painter, .overflowRect.horzCenter() - mark.sizeX * 0.5, font.opticalTop(.overflowRect.vertCenter(), mark.sizeY), colors.softText)
        }

        for it, i in .items where not it.bodyRect.isEmpty()
        {
            let hotBody = i == .hotItem and not .hotArrow
            let hotArr  = i == .hotItem and .hotArrow

            // Body background + text
            if hotBody do
                painter.fillRoundRect(it.bodyRect, m.corner_Control, m.corner_Control, colors.btnIcon_HotBk)

            let restText  = i + 1 == .items.count ? colors.text : (.quiet ? colors.faintText : colors.softText)
            let textColor = hotBody ? colors.btnIcon_HotText : restText
            let iconColor = hotBody ? colors.btnIcon_HotText : colors.btnIcon_Icon

            var cx = it.bodyRect.x + .padX
            if it.icon.isValid()
            {
                var icon = it.icon
                if .iconSize != 0 do
                    icon.sizeX, icon.sizeY = .iconSize
                icon.paint(painter, cx, font.opticalTop(it.bodyRect.vertCenter(), icon.sizeY), iconColor)
                cx += icon.sizeX + .iconGap
            }

            let name = Painter.elideString(it.name, font, Math.max(it.bodyRect.right() - .padX - cx, 0), .deviceScale())
            painter.drawString(cx, font.opticalLineTop(it.bodyRect.vertCenter()), name, font, textColor)

            // Chevron (right-pointing), same orientation as the icon-button right arrow.
            if it.hasArrow
            {
                if hotArr do
                    painter.fillRoundRect(it.arrowRect, m.corner_Control, m.corner_Control, colors.btnIcon_HotBk)

                if .quiet
                {
                    let color = hotArr ? colors.btnIcon_HotText : colors.faintText
                    let width = Painter.measureString(QuietSeparator, font).width
                    painter.drawString(it.arrowRect.horzCenter() - width * 0.5, font.opticalLineTop(it.arrowRect.vertCenter()), QuietSeparator, font, color)
                    continue
                }

                let arrow      = theme.icon(ThemeIcons.ChevronRight, m.chevron_Size)
                let arrowColor = hotArr ? colors.btnIcon_HotText : colors.btnIcon_Icon
                arrow.paint(painter, it.arrowRect.horzCenter() - arrow.sizeX * 0.5, font.opticalTop(it.arrowRect.vertCenter(), arrow.sizeY), arrowColor)
            }
        }
    }
}
