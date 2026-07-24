using Core, Pixel

public enum PopupPos
{
    TopLeft
    AnchorTopCenter
    AnchorBottomCenter
}

#[Swag.EnumFlags]
public enum MenuCtrlFlags
{
    Zero = 0
    NoKeyShortcuts
}

public struct PopupMenuItem
{
    using item: Item
    rightName:  RichString
    popup:      #late *MenuCtrl
    pos:        f32
    size:       f32
    rg:         CommandStateEvent.RenderingHint
    separator:  bool
    disabled:   bool
    checked:    bool
    hidden:     bool
}

public struct MenuCtrl
{
    using frameWnd:   FrameWnd
    onValidateResult: #null func(*MenuCtrl, WndId)
    onComputeItem:    #null func(*MenuCtrl, *PopupMenuItem)
    menuCtrlFlags:    MenuCtrlFlags = Zero

    paddingSel:              f32 = 4
    items:                   ArrayPtr'PopupMenuItem
    hotIdx:                  u32 = Swag.U32.Max
    selectedIdx:             u32 = Swag.U32.Max
    bar:                     bool
    endModal:                bool
    endModalResult:          WndId
    ownerMenu:               #null *MenuCtrl
    subVisible:              #null *MenuCtrl
    timer:                   #null *Timer
    dirtyLayout:             bool
    paintByFrame:            bool
    popupBarItemIdx:         u32 = Swag.U32.Max
    popupBarItemSurfaceRect: Math.Rectangle
    ignoreNextRelease:       bool
}

public impl IWnd for MenuCtrl
{
    private mtd paintBar(painter: *Painter)
    {
        let theme   = .getTheme()
        let colors  = .getThemeColors()
        let rects   = .getThemeRects()
        let metrics = .getThemeMetrics()

        if .dirtyLayout
        {
            .dirtyLayout = false
            .computeLayoutBar()
        }

        // Back
        let clientRect = .getClientRect()
        if .backgroundStyle != .Transparent
        {
            theme.drawSubRect(painter, clientRect, &rects.menuBar_Bk, colors.menuBar_Bk)
            theme.drawSubRect(painter, clientRect, &rects.menuBar_Border, colors.menuBar_Border)
        }

        var labelPos:       Math.Rectangle = undefined
        var colorText:      Color
        var colorRightText: Color

        for i, idx in .items
        {
            if i.hidden do
                continue
            if i.separator do
                continue

            labelPos = .getBarLabelRect(notnull i)

            var format: RichStringFormat
            colorText      = i.disabled ? colors.popupItem_DisabledText : colors.popupItem_Text
            colorRightText = i.disabled ? colors.popupItem_DisabledText : colors.popupItem_RightText

            // Back selection
            let selected = !i.disabled and (.hotIdx == idx or .selectedIdx == idx)
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
            if selected and @isset(i.popup) and .subVisible == i.popup
            {
                backPos.height += metrics.menuPopup_BarItemOverlap
                theme.drawSubRect(painter, backPos, &rects.menuPopup_BarAnchorBk, colors.menuPopup_Bk)
                theme.drawSubRect(painter, backPos, &rects.menuPopup_BarAnchorBorder, colors.menuPopup_Border, interpol: .Pixel)
            }
            elif selected and @isset(i.popup)
            {
                theme.drawSubRect(painter, backPos, &rects.menuBar_PopupSelectedBk, colors.menuPopup_Bk)
                theme.drawSubRect(painter, backPos, &rects.menuBar_PopupSelectedBorder, colors.menuPopup_Border, interpol: .Pixel)
            }
            else do
                theme.drawSubRect(painter, backPos, &rects.menuBar_SelectedBk, colorSel)

            // Icon
            if i.icon.isValid()
            {
                i.icon.sizeX, i.icon.sizeY = i.size - 4
                i.icon.paint(painter, labelPos.x, labelPos.vertCenter() - i.icon.sizeY * 0.5, colorText)
            }

            // Text
            theme.setTextColors(&format, colorText)
            format.horzAlignment = .Left
            format.vertAlignment = .Center
            format.flags         = .Clip
            format.font          = .getFont()
            painter.drawRichString(labelPos, &i.name, format)
        }
    }

    private mtd paintPopup(painter: *Painter)
    {
        let theme   = .getTheme()
        let colors  = .getThemeColors()
        let rects   = .getThemeRects()
        let metrics = .getThemeMetrics()

        // Shadow
        if !.paintByFrame
        {
            let subRect = &theme.rects.menuPopup_Shadow
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
        for i, idx in .items
        {
            if i.hidden do
                continue
            if i.separator and lastIsSeparator do
                continue

            labelPos.x      = clientRect.x
            labelPos.y      = i.pos
            labelPos.width  = clientRect.width
            labelPos.height = i.size

            lastIsSeparator = i.separator
            if i.separator
            {
                painter.drawLine(labelPos.x, labelPos.vertCenter(), labelPos.right(), labelPos.vertCenter(), Pen.createSolid(colors.menuPopup_Separator))
                continue
            }

            colorText      = i.disabled ? colors.popupItem_DisabledText : colors.popupItem_Text
            colorRightText = i.disabled ? colors.popupItem_DisabledText : colors.popupItem_RightText

            // Back selection
            var colorSel: Color
            if .hotIdx == idx and !i.disabled
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

            var iconPos = labelPos
            iconPos.x += metrics.menuPopup_IconMargin
            labelPos.moveLeft(metrics.menuPopup_IconTextMargin + i.size)
            labelPos.width -= i.size

            // Text
            var format: RichStringFormat
            theme.setTextColors(&format, colorText)
            format.horzAlignment = .Left
            format.vertAlignment = .Center
            format.flags         = .Clip
            format.font          = .getFont()
            painter.drawRichString(labelPos, &i.name, format)

            let textCenterY = i.name.isEmpty() ? labelPos.vertCenter() : i.name.boundRect.vertCenter()

            // Icon
            if i.checked or i.rg == .ExclusiveGroup
            {
                var checkPos = iconPos
                checkPos.y                      = textCenterY - i.size * 0.5
                checkPos.width, checkPos.height = i.size

                if i.rg == .ExclusiveGroup
                {
                    theme.drawSubRect(painter, checkPos, &rects.btnRadio_CheckedBorder, colorText)
                    if i.checked do
                        theme.drawSubRect(painter, checkPos, &rects.btnRadio_CheckedMark, colorText)
                }
                else do
                    theme.drawSubRect(painter, checkPos, &rects.btnCheck_CheckedMark, colorText)
            }
            elif i.icon.isValid()
            {
                i.icon.sizeX, i.icon.sizeY = i.size - 4
                i.icon.paint(painter, iconPos.x, textCenterY - i.icon.sizeY * 0.5, colorText)
            }

            // Text right
            if !.menuCtrlFlags.has(.NoKeyShortcuts) and !i.rightName.isEmpty()
            {
                format.palette[0]    = colorRightText
                format.horzAlignment = .Right
                format.vertAlignment = .Center
                format.flags         = .Clip
                format.font          = .getFont()
                painter.drawRichString(labelPos, &i.rightName, format)
            }

            // Right icon
            if @isset(i.popup)
            {
                let icon = theme.getIcon24(ThemeIcons24.RightPopupArrow)
                icon.paint(painter, labelPos.right(), textCenterY - icon.sizeY * 0.5, colorText)
            }
        }
    }

    mtd impl onPaintEvent(evt: *PaintEvent)
    {
        .frameWnd.IWnd.onPaintEvent(evt)
        if .bar do
            .paintBar(evt.bc.painter)
        else do
            .paintPopup(evt.bc.painter)
    }

    mtd impl onTimerEvent(evt: *TimerEvent)
    {
        .hideSubVisible()
        .deleteTimer()
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
                    .timer = .surface.app.addTimer(300'ms, me)
                .timer.restart()
            }

            .hotIdx = hit
            .invalidate()

            if hit != Swag.U32.Max
            {
                var p = .ownerMenu
                while p
                {
                    p.deleteTimer()
                    p = p.ownerMenu
                }
            }
        }

        evt.accepted = true
        if .ignoreNextRelease and evt.kind == .MouseReleased and evt.button == .Left
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
            .deleteTimer()
            .showHotPopup()
        }

        elif .bar and evt.kind == .MousePressed and evt.button == .Left and .hotIdx != Swag.U32.Max
        {
            .hideSubVisible()
            .deleteTimer()
            .showHotPopup()
            if .subVisible do
                .subVisible.ignoreNextRelease = true
        }

        elif .bar and evt.kind == .MouseReleased and evt.button == .Left and .hotIdx != Swag.U32.Max and !.subVisible
        {
            .hideSubVisible()
            .deleteTimer()
            .showHotPopup()
        }

        // On a popup menu, just react to press button
        elif evt.kind == .MouseReleased and evt.button == .Left
        {
            if .hotIdx != Swag.U32.Max
            {
                let hotItem = .items[.hotIdx]
                if @isset(hotItem.popup)
                {
                    .hideSubVisible()
                    .deleteTimer()
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
        let surfaceRect = .getSurfaceRect()
        result.x -= surfaceRect.x
        result.y -= surfaceRect.y
        return result
    }

    private mtd getBarItemHeight()->f32
    {
        return Math.min(.getClientRect().height, .getThemeMetrics().menuBar_Height)
    }

    private mtd getBarLabelRect(item: *PopupMenuItem)->Math.Rectangle
    {
        let clientRect = .getClientRect()
        let height     = .getBarItemHeight()
        return {
            item.pos,
            clientRect.y + (clientRect.height - height) * 0.5,
            item.size,
            height
            }
    }

    private mtd getBarItemRect(item: *PopupMenuItem)->Math.Rectangle
    {
        let metrics = .getThemeMetrics()
        var result  = .getBarLabelRect(item)
        result.x     -= metrics.menuBar_SpaceBetween * 0.5
        result.width += metrics.menuBar_SpaceBetween
        return result
    }

    private mtd getPopupBodyRect()->Math.Rectangle
    {
        let metrics = .getThemeMetrics()
        var result: retval = .getClientRect()
        let anchorHeight = .getPopupBarAnchorHeight()
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

        let theme   = .getTheme()
        let colors  = .getThemeColors()
        let rects   = .getThemeRects()
        let metrics = .getThemeMetrics()

        var anchorRect = .getPopupBarAnchorLocalRect()
        if anchorRect.isEmpty() do
            return

        var anchorBk = anchorRect
        anchorBk.setBottom(bodyRect.y + metrics.menuPopup_BarItemOverlap)
        theme.drawSubRect(painter, anchorBk, &rects.menuPopup_BarAnchorBk, colors.menuPopup_Bk)
        theme.drawSubRect(painter, anchorBk, &rects.menuPopup_BarAnchorBorder, colors.menuPopup_Border, interpol: .Pixel)

        let i = .ownerMenu.items[.popupBarItemIdx]
        var labelPos = anchorRect
        labelPos.x     += metrics.menuBar_SpaceBetween * 0.5
        labelPos.width -= metrics.menuBar_SpaceBetween

        var format: RichStringFormat
        let colorText = i.disabled ? colors.popupItem_DisabledText : colors.menuBar_SelectedText
        theme.setTextColors(&format, colorText)
        format.horzAlignment = .Left
        format.vertAlignment = .Center
        format.flags         = .Clip
        format.font          = .getFont()

        if i.icon.isValid()
        {
            i.icon.sizeX, i.icon.sizeY = i.size - 4
            i.icon.paint(painter, labelPos.x, labelPos.vertCenter() - i.icon.sizeY * 0.5, colorText)
        }

        painter.drawRichString(labelPos, &i.name, format)
    }

    mtd setEndModal(result: WndId)
    {
        var p = &me
        while p.ownerMenu
        {
            p.hide()
            p = p.ownerMenu
        }

        p.endModal       = true
        p.endModalResult = result

        if .onValidateResult and result != null do
            .onValidateResult(me, result)

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

    mtd deleteTimer()
    {
        if !.timer do
            return
        .surface.app.deleteTimer(.timer)
        .timer = null
    }

    public mtd updateState()
    {
        for i in .items
        {
            let evt = .sendComputeCommandStateEvent(i.id)
            if evt.setFlags.has(.Disabled) do
                i.disabled = evt.disabled
            if evt.setFlags.has(.Hidden) do
                i.hidden = evt.hidden
            if evt.setFlags.has(.Icon) do
                i.icon = evt.icon
            if evt.setFlags.has(.LongName) do
                i.name = evt.longName
            elif evt.setFlags.has(.Name) do
                i.name = evt.name
            if evt.setFlags.has(.Shortcut) do
                i.rightName.set(evt.shortcut)
            if evt.setFlags.has(.Checked) do
                i.checked = evt.checked
            if evt.setFlags.has(.RenderingHint) do
                i.rg = evt.renderingHint
        }
    }

    mtd showSubVisible(ptSurface: Math.Point)
    {
        with me.subVisible
        {
            let pt = .parent.surfaceToLocal(ptSurface)
            .setPosition({pt.x, pt.y, .position.width, .position.height})
            .bringToTop()
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
        let hotItem = .items[.hotIdx]
        let metrics = .getThemeMetrics()

        var anchorRect = .localToSurface(.getBarItemRect(notnull hotItem))

        var pos = anchorRect
        pos.x                         -= metrics.menuPopup_ShadowSize
        pos.y                         -= metrics.menuPopup_ShadowSize
        .subVisible                   = hotItem.popup
        .subVisible.ignoreNextRelease = false
        .subVisible.setPopupBarAnchor(.hotIdx, anchorRect)

        // Be sure popup menu is in the client area of the top view
        .subVisible.updateState()
        .subVisible.computeLayoutPopup()
        let topView = .getTopView()
        var pt      = topView.surfaceToLocal({pos.x, pos.y})
        let subPos  = .subVisible.position
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
        let hotItem = .items[.hotIdx]

        var pos         = .getSurfaceRect()
        let sdw         = .getThemeMetrics().menuPopup_ShadowSize
        let surfaceRect = pos
        pos.x                         = pos.right() - sdw
        pos.y                         += hotItem.pos
        pos.y                         -= .padding.y
        .subVisible                   = hotItem.popup
        .subVisible.ignoreNextRelease = false
        .subVisible.clearPopupBarAnchor()

        // Be sure popup menu is in the client area of the top view
        .subVisible.updateState()
        .subVisible.computeLayoutPopup()
        let topView = .getTopView()
        var pt      = topView.surfaceToLocal({pos.x, pos.y})
        pt -= sdw
        let subPos = .subVisible.position
        if pt.x + subPos.width > topView.position.width do
            pt.x = surfaceRect.x - subPos.width
        if pt.y + subPos.height > topView.position.height do
            pt.y = surfaceRect.y - subPos.height

        pt = topView.localToSurface(pt)
        .showSubVisible(pt)
    }

    mtd showHotPopup()
    {
        if .hotIdx == Swag.U32.Max or !@isset(.items[.hotIdx].popup)
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
        let pos        = .surfaceToLocal(surfacePos)
        for i, idx in .items
        {
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
        let pos        = .surfaceToLocal(surfacePos)
        let metrics    = .getThemeMetrics()
        let clientRect = .getClientRect()
        let sl         = metrics.menuPopup_SpaceLines
        var lastIsSeparator = true
        for i, idx in .items
        {
            if i.hidden do
                continue
            if i.separator and lastIsSeparator do
                continue

            let rect = Math.Rectangle{clientRect.x, i.pos - sl * 0.5, clientRect.width, i.size + sl}
            if rect.contains(pos) do
                return cast(u32) idx

            lastIsSeparator = i.separator
        }

        return Swag.U32.Max
    }

    mtd hitTest(surfacePos: Math.Point)->u32
    {
        return .bar ? .hitTestBar(surfacePos) : .hitTestPopup(surfacePos)
    }

    mtd computeLayoutBar()
    {
        let metrics    = .getThemeMetrics()
        let clientRect = .getClientRectPadding()

        var x = clientRect.x

        var fake: Pixel.Painter{fake: true}
        var rsf:  Pixel.RichStringFormat
        rsf.font = .getFont()

        for i, idx in .items
        {
            if i.hidden do
                continue
            if .onComputeItem do
                .onComputeItem(notnull i)
            i.pos = x + metrics.menuBar_SpaceBetween * 0.5
            fake.drawRichString({0, 0, 512, 0}, &i.name, rsf)
            i.size = i.name.boundRect.width
            x      = i.pos + i.size + metrics.menuBar_SpaceBetween * 0.5
        }
    }

    public mtd computeLayoutPopup()
    {
        let metrics = .getThemeMetrics()

        var clientRect = .getPopupBodyRect()
        clientRect.applyPadding(.padding)

        .position.width  = 0
        .position.height = clientRect.y

        var fake: Pixel.Painter{fake: true}
        var rsf:  Pixel.RichStringFormat
        rsf.font = .getFont()

        var lastIsSeparator = true
        for i, idx in .items
        {
            if i.hidden do
                continue
            if i.separator and lastIsSeparator do
                continue

            if .onComputeItem do
                .onComputeItem(notnull i)
            if idx do
                .position.height += metrics.menuPopup_SpaceLines
            i.pos                = .position.height

            lastIsSeparator = i.separator
            if i.separator
            {
                i.size           = metrics.menuPopup_SeparatorHeight
                .position.height += i.size
                continue
            }

            i.size = rsf.font.regular.height

            fake.drawRichString({0, 0, 512, 0}, &i.name, rsf)
            var w = i.name.boundRect.width

            if !.menuCtrlFlags.has(.NoKeyShortcuts) and !i.rightName.isEmpty()
            {
                fake.drawRichString({0, 0, 512, 0}, &i.rightName, rsf)
                w += i.rightName.boundRect.width + rsf.font.regular.height * 3
            }

            .position.width  = Math.max(.position.width, w)
            .position.height += i.size
        }

        // Add shadow size
        if !.paintByFrame do
            .position.width += 2 * metrics.menuPopup_ShadowSize

        .position.width += (2 * rsf.font.regular.height) + (1 * metrics.menuPopup_IconTextMargin)

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
    #[Swag.Discardable]
    func createPopup(parent: *Wnd, id: #null WndId = null, owner: #null *Wnd = null)->*MenuCtrl
    {
        let popupParent = parent == parent.getTopWnd() ? parent : parent.getTopView()
        with let res = Wnd.create'MenuCtrl(popupParent, null, {}, id)
        {
            .owner = owner orelse parent
            .setAllPaddings(.getThemeMetrics().menuPopup_Padding)
            .wndFlags |= .Hidden
        }

        return res
    }

    #[Swag.Discardable]
    func createBar(parent: *Wnd, pos: Math.Rectangle = {}, id: #null WndId = null, owner: #null *Wnd = null)->*MenuCtrl
    {
        with let res = Wnd.create'MenuCtrl(parent, null, pos, id)
        {
            .owner = owner
            let metrics = .getThemeMetrics()
            if .position.height == 0 do
                .position.height = metrics.menuBar_Height
            .setAllPaddings(metrics.menuPopup_Padding)
            .bar = true
        }

        return res
    }

    // Add a new item
    mtd addItem(id: WndId)
    {
        .addItem(null, id)
    }

    // Add a list of items
    mtd addItems(ids: const [..] WndId)
    {
        for id in ids do
            .addItem(null, notnull id)
    }

    // Add a list of items followed by a separator
    mtd addGroup(ids: const [..] WndId)
    {
        .addItems(ids)
        .addSeparator()
    }

    // Add a new item
    mtd addItem(name: #null string, id: WndId, icon: Icon = {}, rightName: #null string = null, disabled = false, checked = false)
    {
        with let mitem = me.items.newPtr()
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
    }

    // Add a new popup item
    mtd addPopup(popup: *MenuCtrl, id: WndId)
    {
        .addPopup(name: null, popup: popup, id: id)
    }

    // Add a new popup item
    mtd addPopup(name: #null string, popup: *MenuCtrl, icon: Icon = {}, id: #null WndId = null)
    {
        with let mitem = me.items.newPtr()
        {
            .name.set(name)
            .icon  = icon
            .popup = popup
            .id    = id
        }

        popup.ownerMenu = me
        .items.add(mitem)
        .dirtyLayout = true
    }

    // Add a separator. Consecutive separators (and a leading one) are collapsed so callers
    // can unconditionally separate groups without producing duplicate dividers.
    mtd addSeparator()
    {
        let last = .items.getLast()
        if last == null or last.separator do
            return
        let item = .items.newPtr()
        item.separator = true
        .items.add(item)
        .dirtyLayout = true
    }

    // Make the popup menu modal
    // Will return the selected id
    mtd doModal(surfacePos: Math.Point, pos = PopupPos.TopLeft, autoDestroy: bool = false)->WndId
    {
        Debug.assert(!.bar)

        .clearPopupBarAnchor()
        .updateState()

        switch pos
        {
        case AnchorTopCenter:
            .paintByFrame = true
            .padding.y    += 4

        case AnchorBottomCenter:
            .paintByFrame = true
            .padding.w    += 4

        default:
            .paintByFrame = false
        }

        .computeLayoutPopup()

        // Be sure popup menu is in the client area of the top view
        var pt = .parent.surfaceToLocal(surfacePos)

        switch pos
        {
        case TopLeft:
            pt -= .getThemeMetrics().menuPopup_ShadowSize
            .setPosition({pt.x, pt.y, .position.width, .position.height})

        case AnchorTopCenter:
            pt.y += .getThemeMetrics().menuPopup_ShadowSize
            .setPosition({pt.x - .position.width * 0.5, pt.y, .position.width, .position.height})
            .anchor    = .Top
            .anchorPos = .position.width * 0.5
            .setFrameFlags(.Borders | .SmallShadow)
            .setFrameForm(.Round)
            .padding.y  += 14
            .paddingSel = 0

        case AnchorBottomCenter:
            pt.y -= .getThemeMetrics().menuPopup_ShadowSize
            .setPosition({pt.x - .position.width * 0.5, pt.y - .position.height, .position.width, .position.height})
            .anchor    = .Bottom
            .anchorPos = .position.width * 0.5
            .setFrameFlags(.Borders | .SmallShadow)
            .setFrameForm(.Round)
            .paddingSel = 0
        }

        .fitPosInParent(simX: true, simY: true)

        .bringToTop()
        .show()
        .captureMouse()

        .endModal             = false
        .endModalResult       = null
        .getApp().inModalLoop += 1
        while !.endModal do
            .surface.app.runFrame()
        .getApp().inModalLoop -= 1

        .hideSubVisible()
        .hide()

        if .endModalResult do
            .postCommandEvent(.endModalResult)

        if autoDestroy do
            .destroy()

        return .endModalResult
    }
}
