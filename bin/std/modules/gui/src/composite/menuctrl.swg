using Core, Pixel

// Selects how a popup menu is positioned around its anchor point.
public enum PopupPosition
{
    TopLeft                // Places the popup's top-left corner at the anchor.
    AnchorTopCenter        // Centers the popup below the anchor.
    AnchorBottomCenter     // Centers the popup above the anchor.
}

// Configures menu presentation.
#[Swag.EnumFlags]
public enum MenuFlags
{
    None = 0          // Shows command shortcut labels.
    HideShortcuts     // Hides command shortcut labels.
}

// Stores one command, submenu, or separator in a [[Gui.MenuCtrl]].
public struct PopupMenuItem
{
    using item: Item           // Embedded item state.
    rightName:  RichString     // Optional right-aligned shortcut label.
    #[Swag.Late]
    popup:     *MenuCtrl                           // Popup associated with this value.
    pos:       f32                                 // Pos associated with this value.
    size:      f32                                 // Size associated with this value.
    rg:        CommandStateEvent.RenderingHint     // Rg associated with this value.
    separator: bool                                // Separator associated with this value.
    disabled:  bool                                // Disabled associated with this value.
    checked:   bool                                // Checked associated with this value.
    hidden:    bool                                // Hidden associated with this value.
}

// Displays either a persistent menu bar or a modal popup menu.
public struct MenuCtrl
{
    using frameWnd: FrameWnd     // Embedded frame window state.

    sigCommandSelected: SigArray'func||(*MenuCtrl, WndId)         // Emitted after a command is selected.
    onPrepareItem:      #null func(*MenuCtrl, *PopupMenuItem)     // Updates an item before menu layout is computed.

    readonly
    {
        flags: MenuFlags = None           // Active presentation options.
        items: ArrayPtr'PopupMenuItem     // Commands, submenus, and separators in display order.
    }

    internal
    {
        paddingSel:              f32 = 4                // Selection-background padding.
        hotIdx:                  u32 = Swag.U32.Max     // Item currently under the pointer.
        selectedIdx:             u32 = Swag.U32.Max     // Item selected by keyboard navigation.
        bar:                     bool                   // Whether this control is a persistent menu bar.
        endModal:                bool                   // Whether the active modal loop should end.
        endModalResult:          #null WndId            // Selected command, or `null` when dismissed.
        ownerMenu:               #null *MenuCtrl        // Parent menu for a submenu.
        subVisible:              #null *MenuCtrl        // Currently visible submenu.
        timer:                   #null *Timer           // Delayed submenu-opening timer.
        dirtyLayout:             bool                   // Whether item bounds need recomputing.
        paintByFrame:            bool                   // Whether the frame paints an anchored popup.
        popupBarItemIdx:         u32 = Swag.U32.Max     // Owning menu-bar item for an anchored popup.
        popupBarItemSurfaceRect: Math.Rectangle         // Owning menu-bar item bounds in surface coordinates.
        ignoreNextRelease:       bool                   // Whether to ignore the release that opened the popup.
    }
}

public impl IWnd for MenuCtrl
{
    private mtd paintBar(painter: *Painter)
    {
        let theme   = .theme()
        let colors  = .themeColors()
        let rects   = .themeRects()
        let metrics = .themeMetrics()

        if .dirtyLayout
        {
            .dirtyLayout = false
            .computeLayoutBar()
        }

        // Back
        let clientRect = .clientRect()
        if .backgroundStyle != .Transparent
        {
            theme.drawSubRect(painter, clientRect, &rects.menuBar_Bk, colors.menuBar_Bk)
            theme.drawSubRect(painter, clientRect, &rects.menuBar_Border, colors.menuBar_Border)
        }

        var labelPos:       Math.Rectangle = undefined
        var colorText:      Color
        var colorRightText: Color

        for i, [idx] in .items
        {
            let it = notnull i
            if it.hidden do
                continue
            if it.separator do
                continue

            labelPos = .getBarLabelRect(notnull i)

            var format: RichStringFormat
            colorText      = it.disabled ? colors.popupItem_DisabledText : colors.popupItem_Text
            colorRightText = it.disabled ? colors.popupItem_DisabledText : colors.popupItem_RightText

            // Back selection
            let selected = !it.disabled and (.hotIdx == idx or .selectedIdx == idx)
            var colorSel: Color
            if selected
            {
                colorSel       = colors.menuBar_SelectedBk
                colorText      = colors.menuBar_SelectedText
                colorRightText = colors.popupItem_HotRightText
            }

            var backPos = labelPos
            backPos.x     -= metrics.menuBar_SpaceBetween * 0.5
            backPos.width += metrics.menuBar_SpaceBetween
            if selected and @isset(it.popup) and .subVisible == it.popup
            {
                backPos.height += metrics.menuPopup_BarItemOverlap
                theme.drawSubRect(painter, backPos, &rects.menuPopup_BarAnchorBk, colors.menuPopup_Bk)
                theme.drawSubRect(painter, backPos, &rects.menuPopup_BarAnchorBorder, colors.menuPopup_Border, interpol: .Pixel)
            }
            elif selected and @isset(it.popup)
            {
                theme.drawSubRect(painter, backPos, &rects.menuBar_PopupSelectedBk, colors.menuPopup_Bk)
                theme.drawSubRect(painter, backPos, &rects.menuBar_PopupSelectedBorder, colors.menuPopup_Border, interpol: .Pixel)
            }
            else do
                theme.drawSubRect(painter, backPos, &rects.menuBar_SelectedBk, colorSel)

            if selected and colors.activeRail.a
            {
                let rail = Math.Rectangle{backPos.x, labelPos.bottom() - 4, backPos.width, 4}
                painter.fillRect(rail, colors.activeRail)
            }

            // Icon
            if it.icon.isValid()
            {
                var icon = it.icon
                icon.sizeX, icon.sizeY = it.size - 4
                icon.paint(painter, labelPos.x, labelPos.vertCenter() - icon.sizeY * 0.5, colorText)
            }

            // Text
            theme.setTextColors(&format, colorText)
            format.horzAlignment = .Left
            format.vertAlignment = .Center
            format.flags         = .Clip
            format.font          = .font()
            painter.drawRichString(labelPos, &it.name, format)
        }
    }

    private mtd paintPopup(painter: *Painter)
    {
        let theme   = .theme()
        let colors  = .themeColors()
        let rects   = .themeRects()
        let metrics = .themeMetrics()

        // Shadow
        if !.paintByFrame
        {
            let subRect      = &theme.rects.menuPopup_Shadow
            let anchorHeight = .getPopupBarAnchorHeight()
            theme.drawSubRect(painter, {0, anchorHeight, .position.width, .position.height - anchorHeight}, subRect, colors.menuPopup_Shadow)
        }

        // Back
        var clientRect = .getPopupBodyRect()
        if !.paintByFrame
        {
            theme.drawSubRect(painter, clientRect, &rects.menuPopup_Bk, colors.menuPopup_Bk)
            theme.drawSubRect(painter, clientRect, &rects.menuPopup_Border, colors.menuPopup_Border, interpol: .Pixel)
        }

        .paintPopupBarAnchor(painter, clientRect)
        clientRect.applyPadding(.padding)

        var labelPos:       Math.Rectangle = undefined
        var colorText:      Color
        var colorRightText: Color

        var lastIsSeparator = true
        for i, [idx] in .items
        {
            let it = notnull i
            if it.hidden do
                continue
            if it.separator and lastIsSeparator do
                continue

            labelPos.x      = clientRect.x
            labelPos.y      = it.pos
            labelPos.width  = clientRect.width
            labelPos.height = it.size

            lastIsSeparator = it.separator
            if it.separator
            {
                painter.drawLine(labelPos.x, labelPos.vertCenter(), labelPos.right(), labelPos.vertCenter(), Pen.createSolid(colors.menuPopup_Separator))
                continue
            }

            colorText      = it.disabled ? colors.popupItem_DisabledText : colors.popupItem_Text
            colorRightText = it.disabled ? colors.popupItem_DisabledText : colors.popupItem_RightText

            // Back selection
            var colorSel: Color
            let isHot = .hotIdx == idx and !it.disabled
            if isHot
            {
                colorSel       = colors.popupItem_HotBk
                colorText      = colors.popupItem_HotText
                colorRightText = colors.popupItem_HotRightText
            }

            var backPos = labelPos
            backPos.y      -= metrics.menuPopup_SpaceLines * 0.5
            backPos.height += metrics.menuPopup_SpaceLines
            backPos.inflate(.paddingSel, 0)
            theme.drawSubRect(painter, backPos, &rects.menuPopup_HotBk, colorSel)
            if isHot and colors.activeRail.a
            {
                let rail = Math.Rectangle{backPos.x, backPos.y, 4, backPos.height}
                painter.fillRect(rail, colors.activeRail)
            }

            var iconPos = labelPos
            iconPos.x += metrics.menuPopup_IconMargin
            labelPos.moveLeft(metrics.menuPopup_IconTextMargin + it.size)
            labelPos.width -= it.size

            // Text
            var format: RichStringFormat
            theme.setTextColors(&format, colorText)
            format.horzAlignment = .Left
            format.vertAlignment = .Center
            format.flags         = .Clip
            format.font          = .font()
            painter.drawRichString(labelPos, &it.name, format)

            let textCenterY = it.name.isEmpty() ? labelPos.vertCenter() : it.name.boundRect.vertCenter()

            // Icon
            if it.checked or it.rg == .ExclusiveGroup
            {
                var checkPos = iconPos
                checkPos.y                      = textCenterY - it.size * 0.5
                checkPos.width, checkPos.height = it.size

                if it.rg == .ExclusiveGroup
                {
                    theme.drawSubRect(painter, checkPos, &rects.btnRadio_CheckedBorder, colorText)
                    if it.checked do
                        theme.drawSubRect(painter, checkPos, &rects.btnRadio_CheckedMark, colorText)
                }
                else do
                    theme.drawSubRect(painter, checkPos, &rects.btnCheck_CheckedMark, colorText)
            }
            elif it.icon.isValid()
            {
                var icon = it.icon
                icon.sizeX, icon.sizeY = it.size - 4
                icon.paint(painter, iconPos.x, textCenterY - icon.sizeY * 0.5, colorText)
            }

            // Text right
            if !.flags.has(.HideShortcuts) and !it.rightName.isEmpty()
            {
                format.palette[0]    = colorRightText
                format.horzAlignment = .Right
                format.vertAlignment = .Center
                format.flags         = .Clip
                format.font          = .font()
                painter.drawRichString(labelPos, &it.rightName, format)
            }

            // Right icon
            if @isset(it.popup)
            {
                let icon = theme.icon24(ThemeIcons24.RightPopupArrow)
                icon.paint(painter, labelPos.right(), textCenterY - icon.sizeY * 0.5, colorText)
            }
        }
    }

    mtd impl onPaint(evt: *PaintEvent)
    {
        .frameWnd.IWnd.onPaint(evt)
        if .bar do
            .paintBar(evt.paintContext.painter)
        else do
            .paintPopup(evt.paintContext.painter)
    }

    mtd impl onTimerEvent(evt: *TimerEvent)
    {
        .hideSubVisible()
        .removeTimer()
        .showHotPopup()
    }

    mtd impl onMouseEvent(evt: *MouseEvent)
    {
        let hit = .hitTest(evt.surfacePos)
        if hit != .hotIdx
        {
            // Timer to auto open/hide sub menus
            if !.bar
            {
                if !.timer do
                    .timer = .surface!.app.addTimer(300'ms, me)
                let timer = notnull .timer
                timer.restart()
            }

            .hotIdx = hit
            .invalidate()

            if hit != Swag.U32.Max
            {
                var p = .ownerMenu
                while p
                {
                    p.removeTimer()
                    p = p.ownerMenu
                }
            }
        }

        evt.accepted = true
        if .ignoreNextRelease and evt.kind == .Released and evt.button == .Left
        {
            .ignoreNextRelease = false
            return
        }

        if .hotIdx == Swag.U32.Max and .ownerMenu
        {
            .ownerMenu.onMouseEvent(evt)
            return
        }

        if .hotIdx == Swag.U32.Max and .bar and !.subVisible
        {
            evt.accepted = false
            return
        }

        // If this is a bar, then track sub popup if one is currently open
        if .bar and .subVisible and .hotIdx != Swag.U32.Max
        {
            .hideSubVisible()
            .removeTimer()
            .showHotPopup()
        }

        elif .bar and evt.kind == .Pressed and evt.button == .Left and .hotIdx != Swag.U32.Max
        {
            .hideSubVisible()
            .removeTimer()
            .showHotPopup()
            if .subVisible do
                .subVisible.ignoreNextRelease = true
        }

        elif .bar and evt.kind == .Released and evt.button == .Left and .hotIdx != Swag.U32.Max and !.subVisible
        {
            .hideSubVisible()
            .removeTimer()
            .showHotPopup()
        }

        // On a popup menu, just react to press button
        elif evt.kind == .Released and evt.button == .Left
        {
            if .hotIdx != Swag.U32.Max
            {
                let hotItem = notnull .items[.hotIdx]
                if @isset(hotItem.popup)
                {
                    .hideSubVisible()
                    .removeTimer()
                    .showHotPopup()
                }
                elif !hotItem.separator and !hotItem.disabled
                {
                    .setEndModal(hotItem.id)
                }
            }
            else
            {
                .setEndModal(null)
            }
        }
    }
}

impl MenuCtrl
{
    private mtd hasPopupBarAnchor()->bool
    {
        return .popupBarItemIdx != Swag.U32.Max and .ownerMenu and .ownerMenu.bar
    }

    private mtd clearPopupBarAnchor()
    {
        .popupBarItemIdx = Swag.U32.Max
        .popupBarItemSurfaceRect.clear()
    }

    private mtd setPopupBarAnchor(itemIdx: u32, itemSurfaceRect: Math.Rectangle)
    {
        .popupBarItemIdx         = itemIdx
        .popupBarItemSurfaceRect = itemSurfaceRect
    }

    private mtd getPopupBarAnchorHeight()->f32
    {
        return .hasPopupBarAnchor() ? .popupBarItemSurfaceRect.height : 0
    }

    private mtd getPopupBarAnchorLocalRect()->Math.Rectangle
    {
        var result: retval = .popupBarItemSurfaceRect
        let surfaceRect    = .surfaceRect()
        result.x -= surfaceRect.x
        result.y -= surfaceRect.y
        return result
    }

    private mtd getBarItemHeight()->f32
    {
        return Math.min(.clientRect().height, .themeMetrics().menuBar_Height)
    }

    private mtd getBarLabelRect(item: *PopupMenuItem)->Math.Rectangle
    {
        let clientRect = .clientRect()
        let height     = .getBarItemHeight()
        return {
            item.pos,
            clientRect.y + (clientRect.height - height) * 0.5,
            item.size,
            height}
    }

    private mtd getBarItemRect(item: *PopupMenuItem)->Math.Rectangle
    {
        let metrics = .themeMetrics()
        var result  = .getBarLabelRect(item)
        result.x     -= metrics.menuBar_SpaceBetween * 0.5
        result.width += metrics.menuBar_SpaceBetween
        return result
    }

    private mtd getPopupBodyRect()->Math.Rectangle
    {
        let metrics        = .themeMetrics()
        var result: retval = .clientRect()
        let anchorHeight   = .getPopupBarAnchorHeight()
        if anchorHeight
        {
            result.y      += anchorHeight
            result.height -= anchorHeight
        }

        if !.paintByFrame do
            result.inflate(-metrics.menuPopup_ShadowSize)
        return result
    }

    private mtd paintPopupBarAnchor(painter: *Painter, bodyRect: Math.Rectangle)
    {
        if !.hasPopupBarAnchor() do
            return

        let theme   = .theme()
        let colors  = .themeColors()
        let rects   = .themeRects()
        let metrics = .themeMetrics()

        var anchorRect = .getPopupBarAnchorLocalRect()
        if anchorRect.isEmpty() do
            return

        var anchorBk = anchorRect
        anchorBk.setBottom(bodyRect.y + metrics.menuPopup_BarItemOverlap)
        theme.drawSubRect(painter, anchorBk, &rects.menuPopup_BarAnchorBk, colors.menuPopup_Bk)
        theme.drawSubRect(painter, anchorBk, &rects.menuPopup_BarAnchorBorder, colors.menuPopup_Border, interpol: .Pixel)

        let i        = notnull .ownerMenu!.items[.popupBarItemIdx]
        var labelPos = anchorRect
        labelPos.x     += metrics.menuBar_SpaceBetween * 0.5
        labelPos.width -= metrics.menuBar_SpaceBetween

        var format: RichStringFormat
        let colorText = i.disabled ? colors.popupItem_DisabledText : colors.menuBar_SelectedText
        theme.setTextColors(&format, colorText)
        format.horzAlignment = .Left
        format.vertAlignment = .Center
        format.flags         = .Clip
        format.font          = .font()

        if i.icon.isValid()
        {
            var icon = i.icon
            icon.sizeX, icon.sizeY = i.size - 4
            icon.paint(painter, labelPos.x, labelPos.vertCenter() - icon.sizeY * 0.5, colorText)
        }

        painter.drawRichString(labelPos, &i.name, format)
    }

    mtd setEndModal(result: #null WndId)
    {
        var p = &me
        while p.ownerMenu
        {
            p.hide()
            p = p.ownerMenu
        }

        p.endModal       = true
        p.endModalResult = result

        if result != null do
            .sigCommandSelected.call(me, notnull result)

        if .bar
        {
            .hideSubVisible()
            .postCommandEvent(result)
            .setFocus()
        }

        if p.bar
        {
            p.selectedIdx = Swag.U32.Max
            p.hotIdx      = Swag.U32.Max
            p.subVisible  = null
            p.postCommandEvent(result)
        }
    }

    mtd hideSubVisible()
    {
        while .subVisible
        {
            .subVisible.ignoreNextRelease = false
            .subVisible.hide()
            .subVisible = .subVisible.subVisible
        }

        .selectedIdx = Swag.U32.Max
        if !.bar do
            .captureMouse()
        else do
            .releaseMouse()
    }

    mtd removeTimer()
    {
        if !.timer do
            return
        let srf = notnull .surface
        srf.app.removeTimer(.timer)
        .timer = null
    }

    // Updates state.
    public mtd updateState()
    {
        for i in .items
        {
            let it  = notnull i
            let evt = .sendComputeCommandStateEvent(it.id)
            if evt.updatedFields.has(.Disabled) do
                it.disabled = evt.disabled
            if evt.updatedFields.has(.Hidden) do
                it.hidden = evt.hidden
            if evt.updatedFields.has(.Icon) do
                it.icon = evt.icon
            if evt.updatedFields.has(.LongName) do
                it.name = evt.longName
            elif evt.updatedFields.has(.Name) do
                it.name = evt.name
            if evt.updatedFields.has(.Shortcut) do
                it.rightName.set(evt.shortcut)
            if evt.updatedFields.has(.Checked) do
                it.checked = evt.checked
            if evt.updatedFields.has(.RenderingHint) do
                it.rg = evt.renderingHint
        }
    }

    mtd showSubVisible(ptSurface: Math.Point)
    {
        with me.subVisible
        {
            let pt = .parent!.surfaceToLocal(ptSurface)
            .setPosition({pt.x, pt.y, .position.width, .position.height})
            .bringToFront()
            .show()
            .captureMouse()
            .hotIdx      = Swag.U32.Max
            .selectedIdx = Swag.U32.Max
            .subVisible  = null
            .timer       = null
        }
    }

    mtd showHotPopupBar()
    {
        .selectedIdx = .hotIdx
        let hotItem = notnull .items[.hotIdx]
        let metrics = .themeMetrics()

        var anchorRect = .localToSurface(.getBarItemRect(hotItem))

        var pos = anchorRect
        pos.x -= metrics.menuPopup_ShadowSize
        pos.y -= metrics.menuPopup_ShadowSize
        let sub = hotItem.popup
        .subVisible           = sub
        sub.ignoreNextRelease = false
        sub.setPopupBarAnchor(.hotIdx, anchorRect)

        // Be sure popup menu is in the client area of the top view
        sub.updateState()
        sub.computeLayoutPopup()
        let topView = .topView()
        var pt      = topView.surfaceToLocal({pos.x, pos.y})
        let subPos  = sub.position
        if pt.x + subPos.width > topView.position.width do
            pt.x = topView.position.width - subPos.width
        if pt.y + subPos.height > topView.position.height do
            pt.y = topView.position.height - subPos.height

        pt = topView.localToSurface(pt)
        .showSubVisible(pt)
    }

    mtd showHotPopupPopup()
    {
        .selectedIdx = .hotIdx
        let hotItem = notnull .items[.hotIdx]

        var pos         = .surfaceRect()
        let sdw         = .themeMetrics().menuPopup_ShadowSize
        let surfaceRect = pos
        pos.x = pos.right() - sdw
        pos.y += hotItem.pos
        pos.y -= .padding.y
        let sub = hotItem.popup
        .subVisible           = sub
        sub.ignoreNextRelease = false
        sub.clearPopupBarAnchor()

        // Be sure popup menu is in the client area of the top view
        sub.updateState()
        sub.computeLayoutPopup()
        let topView = .topView()
        var pt      = topView.surfaceToLocal({pos.x, pos.y})
        pt -= sdw
        let subPos = sub.position
        if pt.x + subPos.width > topView.position.width do
            pt.x = surfaceRect.x - subPos.width
        if pt.y + subPos.height > topView.position.height do
            pt.y = surfaceRect.y - subPos.height

        pt = topView.localToSurface(pt)
        .showSubVisible(pt)
    }

    mtd showHotPopup()
    {
        if .hotIdx == Swag.U32.Max or !@isset(.items[.hotIdx]!.popup)
        {
            .selectedIdx = Swag.U32.Max
            return
        }

        if .bar do
            .showHotPopupBar()
        else do
            .showHotPopupPopup()
    }

    mtd hitTestBar(surfacePos: Math.Point)->u32
    {
        let pos = .surfaceToLocal(surfacePos)
        for iIt, [idx] in .items
        {
            let i = notnull iIt
            if i.hidden do
                continue
            if i.separator do
                continue

            if .getBarItemRect(notnull i).contains(pos) do
                return cast(u32) idx
        }

        return Swag.U32.Max
    }

    mtd hitTestPopup(surfacePos: Math.Point)->u32
    {
        let pos             = .surfaceToLocal(surfacePos)
        let metrics         = .themeMetrics()
        let clientRect      = .clientRect()
        let sl              = metrics.menuPopup_SpaceLines
        var lastIsSeparator = true
        for i, [idx] in .items
        {
            let it = notnull i
            if it.hidden do
                continue
            if it.separator and lastIsSeparator do
                continue

            let rect = Math.Rectangle{clientRect.x, it.pos - sl * 0.5, clientRect.width, it.size + sl}
            if rect.contains(pos) do
                return cast(u32) idx

            lastIsSeparator = it.separator
        }

        return Swag.U32.Max
    }

    mtd hitTest(surfacePos: Math.Point)->u32
    {
        return .bar ? .hitTestBar(surfacePos) : .hitTestPopup(surfacePos)
    }

    mtd computeLayoutBar()
    {
        let metrics    = .themeMetrics()
        let clientRect = .paddedClientRect()

        var x = clientRect.x

        var fake: Pixel.Painter
        fake.begin(layoutOnly: true)
        defer fake.end()
        var rsf: Pixel.RichStringFormat
        rsf.font = .font()

        for i, [idx] in .items
        {
            let it = notnull i
            if it.hidden do
                continue
            if .onPrepareItem do
                .onPrepareItem(notnull i)
            it.pos = x + metrics.menuBar_SpaceBetween * 0.5
            fake.drawRichString({0, 0, 512, 0}, &it.name, rsf)
            it.size = it.name.boundRect.width
            x       = it.pos + it.size + metrics.menuBar_SpaceBetween * 0.5
        }
    }

    // Computes layout popup.
    public mtd computeLayoutPopup()
    {
        let metrics = .themeMetrics()

        var clientRect = .getPopupBodyRect()
        clientRect.applyPadding(.padding)

        .position.width  = 0
        .position.height = clientRect.y

        var fake: Pixel.Painter
        fake.begin(layoutOnly: true)
        defer fake.end()
        var rsf: Pixel.RichStringFormat
        rsf.font = .font()

        var lastIsSeparator = true
        for i, [idx] in .items
        {
            let it = notnull i
            if it.hidden do
                continue
            if it.separator and lastIsSeparator do
                continue

            if .onPrepareItem do
                .onPrepareItem(notnull i)
            if idx do
                .position.height += metrics.menuPopup_SpaceLines
            it.pos = .position.height

            lastIsSeparator = it.separator
            if it.separator
            {
                it.size          = metrics.menuPopup_SeparatorHeight
                .position.height += it.size
                continue
            }

            it.size = rsf.font.regular!.height

            fake.drawRichString({0, 0, 512, 0}, &it.name, rsf)
            var w = it.name.boundRect.width

            if !.flags.has(.HideShortcuts) and !it.rightName.isEmpty()
            {
                fake.drawRichString({0, 0, 512, 0}, &it.rightName, rsf)
                w += it.rightName.boundRect.width + rsf.font.regular!.height * 3
            }

            .position.width  = Math.max(.position.width, w)
            .position.height += it.size
        }

        // Add shadow size
        if !.paintByFrame do
            .position.width += 2 * metrics.menuPopup_ShadowSize

        .position.width += (2 * rsf.font.regular!.height) + (1 * metrics.menuPopup_IconTextMargin)

        if .hasPopupBarAnchor() and !.paintByFrame
        {
            let bodyWidth = .position.width - 2 * metrics.menuPopup_ShadowSize
            if bodyWidth < .popupBarItemSurfaceRect.width do
                .position.width += .popupBarItemSurfaceRect.width - bodyWidth
        }

        if !.paintByFrame do
            .position.height += metrics.menuPopup_ShadowSize

        // Add padding
        .position.width  += .padding.x + .padding.z
        .position.height += .padding.w
    }
}

public impl MenuCtrl
{
    // Selects whether an enclosing frame paints the popup border and shadow.
    mtd setFramePainting(enabled: bool)
    {
        if .paintByFrame == enabled do
            return
        .paintByFrame = enabled
        .dirtyLayout  = true
        .invalidate()
    }

    // Reports whether the current modal popup loop has ended.
    mtd const isModalEnded()->bool => .endModal

    // Returns the selected modal command, or null when dismissed or still running.
    mtd const modalResult()->#null WndId => .endModalResult

    // Adds and removes presentation options, then invalidates cached layout.
    mtd updateFlags(add: MenuFlags = .None, remove = MenuFlags.None)
    {
        var flags = .flags
        flags.add(add)
        flags.remove(remove)
        if flags == .flags do
            return
        .flags       = flags
        .dirtyLayout = true
        .invalidate()
    }

    // Creates a hidden popup menu owned by `owner`, or by `parent` when omitted.
    #[Swag.Discardable]
    func createPopup(parent: *Wnd, id: #null WndId = null, owner: #null *Wnd = null)->*MenuCtrl
    {
        Debug.assert(parent != null)
        let popupParent = parent == parent.topWindow() ? parent : parent.topView()
        with let res = Wnd.create'MenuCtrl(popupParent, null, {}, id)
        {
            .owner = owner orelse parent
            .setAllPaddings(.themeMetrics().menuPopup_Padding)
            .wndFlags |= .Hidden
        }

        return res
    }

    // Creates a persistent horizontal menu bar.
    #[Swag.Discardable]
    func createBar(parent: *Wnd, pos: Math.Rectangle = {}, id: #null WndId = null, owner: #null *Wnd = null)->*MenuCtrl
    {
        Debug.assert(parent != null)
        with let res = Wnd.create'MenuCtrl(parent, null, pos, id)
        {
            .owner = owner
            let metrics = .themeMetrics()
            if .position.height == 0 do
                .position.height = metrics.menuBar_Height
            .setAllPaddings(metrics.menuPopup_Padding)
            .bar = true
        }

        return res
    }

    // Returns the item at `index`.
    mtd const itemAt(index: u32)->*PopupMenuItem
    {
        Debug.assert(index < .items.count, "menu item index is out of range")
        return notnull .items[index]
    }

    // Removes one item and invalidates cached menu layout.
    mtd removeItemAt(index: u32)
    {
        Debug.assert(index < .items.count, "menu item index is out of range")
        .hideSubVisible()
        .removeTimer()
        .items.deleteAt(index)
        .hotIdx      = Swag.U32.Max
        .selectedIdx = Swag.U32.Max
        .dirtyLayout = true
        .invalidate()
    }

    // Removes every command, submenu entry, and separator.
    mtd clear()
    {
        if .items.isEmpty() do
            return
        .hideSubVisible()
        .removeTimer()
        .items.clear()
        .hotIdx      = Swag.U32.Max
        .selectedIdx = Swag.U32.Max
        .dirtyLayout = true
        .invalidate()
    }

    // Adds a command whose label, icon, and state come from its command identifier.
    #[Swag.Discardable]
    mtd addItem(id: WndId)->*PopupMenuItem
    {
        return .addItem(null, id)
    }

    // Adds commands whose labels, icons, and states come from their identifiers.
    mtd addItems(ids: const [..] WndId)
    {
        for id in ids do
            .addItem(null, notnull id)
    }

    // Adds a command group followed by a separator.
    mtd addGroup(ids: const [..] WndId)
    {
        .addItems(ids)
        .addSeparator()
    }

    // Adds a command with explicit presentation and returns its mutable item descriptor.
    #[Swag.Discardable]
    mtd addItem(name: #null string, id: WndId, icon: Icon = {}, rightName: #null string = null, disabled = false, checked = false)->*PopupMenuItem
    {
        with let mitem = me.items.allocate()
        {
            .name.set(name)
            .icon      = icon
            .id        = id
            .rightName = rightName orelse ""
            .disabled  = disabled
            .checked   = checked
        }

        .items.add(mitem)
        .dirtyLayout = true
        return mitem
    }

    // Adds a submenu whose presentation comes from a command identifier.
    #[Swag.Discardable]
    mtd addPopup(popup: *MenuCtrl, id: WndId)->*PopupMenuItem
    {
        return .addPopup(name: null, popup: popup, id: id)
    }

    // Adds a submenu with explicit presentation and returns its mutable item descriptor.
    #[Swag.Discardable]
    mtd addPopup(name: #null string, popup: *MenuCtrl, icon: Icon = {}, id: #null WndId = null)->*PopupMenuItem
    {
        with let mitem = me.items.allocate()
        {
            .name.set(name)
            .icon  = icon
            .popup = popup
            .id    = id
        }

        popup.ownerMenu = me
        .items.add(mitem)
        .dirtyLayout = true
        return mitem
    }

    // Add a separator. Consecutive separators (and a leading one) are collapsed so callers
    // can unconditionally separate groups without producing duplicate dividers.
    mtd addSeparator()
    {
        let last = .items.last()
        if !last or last.separator do
            return
        let item = .items.allocate()
        item.separator = true
        .items.add(item)
        .dirtyLayout = true
    }

    // Runs a popup menu modally and returns its selected command, or null when dismissed.
    // When `autoDestroy` is true, the menu destroys itself after the modal loop ends.
    mtd doModal(surfacePos: Math.Point, pos = PopupPosition.TopLeft, autoDestroy: bool = false)->#null WndId
    {
        Debug.assert(!.bar)

        .clearPopupBarAnchor()
        .updateState()

        switch pos
        {
        case .AnchorTopCenter:
            .paintByFrame = true
            .padding.y    += 4

        case .AnchorBottomCenter:
            .paintByFrame = true
            .padding.w    += 4

        default:
            .paintByFrame = false
        }

        .computeLayoutPopup()

        // Be sure popup menu is in the client area of the top view
        var pt = .parent!.surfaceToLocal(surfacePos)

        switch pos
        {
        case .TopLeft:
            pt -= .themeMetrics().menuPopup_ShadowSize
            .setPosition({pt.x, pt.y, .position.width, .position.height})

        case .AnchorTopCenter:
            pt.y += .themeMetrics().menuPopup_ShadowSize
            .setPosition({pt.x - .position.width * 0.5, pt.y, .position.width, .position.height})
            .anchor         = .Top
            .anchorPosition = .position.width * 0.5
            .setFrameFlags(.Borders | .SmallShadow)
            .setFrameForm(.themeColors().activeRail.a ? .Square : .Round)
            .padding.y  += 14
            .paddingSel = 0

        case .AnchorBottomCenter:
            pt.y -= .themeMetrics().menuPopup_ShadowSize
            .setPosition({pt.x - .position.width * 0.5, pt.y - .position.height, .position.width, .position.height})
            .anchor         = .Bottom
            .anchorPosition = .position.width * 0.5
            .setFrameFlags(.Borders | .SmallShadow)
            .setFrameForm(.themeColors().activeRail.a ? .Square : .Round)
            .paddingSel = 0
        }

        .fitPosInParent(simX: true, simY: true)

        .bringToFront()
        .show()
        .captureMouse()

        .endModal          = false
        .endModalResult    = null
        .app().inModalLoop += 1
        let srf = notnull .surface
        while !.endModal do
            srf.app.runFrame()
        .app().inModalLoop -= 1

        .hideSubVisible()
        .hide()

        if .endModalResult do
            .postCommandEvent(.endModalResult)

        if autoDestroy do
            .destroy()

        return .endModalResult
    }
}
