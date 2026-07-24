#global public

using Core, Pixel

enum TabForm
{
    Flat
    Round
    Button
    PushButton
}

enum TabBarForm
{
    Transparent
    Flat
    FlatRound
    Round
}

enum TabItemForm
{
    Transparent
    Flat
    Round
    Button
    PushButton
}

enum TabViewForm
{
    None
    Flat
    Round
}

enum TabBarLayout
{
    Divide
    Fixed
    Auto
}

struct TabItem
{
    using item: Item
    pos:        f32
    width:      f32
    view:       #null *Wnd
    aniImg:     BlendColor
    aniBorder:  BlendColor
    aniText:    BlendColor
}

struct Tab
{
    using wnd: Wnd

    barForm                   = TabBarForm.Flat
    itemForm                  = TabItemForm.Flat
    viewForm                  = TabViewForm.Flat
    barLayout                 = TabBarLayout.Divide
    itemFixedLayoutWidth: f32 = 100
    itemAutoLayoutMargin: f32 = 25
    itemMinWidth:         f32 = 25

    sigSelChanged: SigArray'func||(*Tab)

    buttonPopup:     #null *IconButton
    views:           ArrayPtr'TabItem
    popup:           #null *PopupListCtrl
    selectedIdx:     u32
    firstVisibleIdx: u32
    hotIdx:          u32 = Swag.U32.Max
    barHeight:       f32
    mostRightPos:    f32
}

impl IWnd for Tab
{
    mtd paintItem(painter: *Painter, v: *TabItem, idx: u32)
    {
        var clientRect = .getClientRect()
        clientRect.height = Math.min(.barHeight, clientRect.height)

        var labelPos = clientRect
        labelPos.width = v.width
        labelPos.x     = v.pos

        let theme   = .getTheme()
        let metrics = .getThemeMetrics()
        let colors  = .getThemeColors()
        let rects   = .getThemeRects()

        // Item image
        var subRect:       #null *ThemeImageRect
        var subRectBorder: #null *ThemeImageRect
        var colorImg:      Color
        var colorText:     Color
        var colorBorder:   Color

        #[Swag.Complete]
        switch .itemForm
        {
        case Flat:
            if idx == .selectedIdx
            {
                subRect   = &rects.tabItem_FlatSelected
                colorImg  = colors.tabItem_FlatSelected
                colorText = colors.tabItem_SelectedText
            }
            elif idx == .hotIdx
            {
                subRect   = &rects.tabItem_FlatSelected
                colorImg  = colors.tabItem_FlatHot
                colorText = colors.tabItem_HotText
            }
            else
            {
                colorText = colors.tabItem_Text
            }

        case Round:
            if idx == .selectedIdx
            {
                subRect   = &rects.tabItem_RoundSelected
                colorImg  = colors.tabItem_RoundSelected
                colorText = colors.tabItem_SelectedText
            }
            elif idx == .hotIdx
            {
                subRect   = &rects.tabItem_RoundHot
                colorImg  = colors.tabItem_RoundHot
                colorText = colors.tabItem_HotText
            }
            else
            {
                colorText = colors.tabItem_Text
            }

        case Button:
            if idx == .selectedIdx
            {
                subRect   = &rects.tabItem_ButtonSelected
                colorImg  = colors.tabItem_ButtonSelected
                colorText = colors.tabItem_SelectedText
            }
            elif idx == .hotIdx
            {
                subRect   = &rects.tabItem_ButtonHot
                colorImg  = colors.tabItem_ButtonHot
                colorText = colors.tabItem_HotText
            }
            else
            {
                colorText = colors.tabItem_Text
            }

        case PushButton:
            if idx == .selectedIdx
            {
                subRect       = &rects.tabItem_PushButtonSelected
                subRectBorder = &rects.tabItem_PushButtonBorder
                colorImg      = colors.tabItem_PushButtonSelected
                colorText     = colors.tabItem_PushButtonSelectedText
                colorBorder   = colors.tabItem_PushButtonSelectedBorder
            }
            elif idx == .hotIdx
            {
                subRect       = &rects.tabItem_PushButtonHot
                subRectBorder = &rects.tabItem_PushButtonBorder
                colorImg      = colors.tabItem_PushButtonHot
                colorText     = colors.tabItem_PushButtonHotText
                colorBorder   = colors.tabItem_PushButtonHotBorder
            }
            else
            {
                subRect       = &rects.tabItem_PushButtonBk
                subRectBorder = &rects.tabItem_PushButtonBorder
                colorImg      = colors.tabItem_PushButtonBk
                colorText     = colors.tabItem_PushButtonText
                colorBorder   = colors.tabItem_PushButtonBorder
            }

        case Transparent:
            break
        }

        v.aniImg.apply(me, colorImg)
        v.aniBorder.apply(me, colorBorder)

        if subRect do
            theme.drawSubRect(painter, labelPos, subRect, v.aniImg.cur())
        if subRectBorder do
            theme.drawSubRect(painter, labelPos, subRectBorder, v.aniBorder.cur(), false)

        var format: RichStringFormat
        v.aniText.apply(me, colorText)
        theme.setTextColors(&format, v.aniText.cur())
        format.horzAlignment = .Center
        format.vertAlignment = .Center
        format.flags         = .Clip
        format.font          = .getFont()
        Theme.drawIconText(painter, labelPos, v.icon, &v.name, format, metrics.iconText_Margin)
    }

    mtd impl onPaintEvent(evt: *PaintEvent)
    {
        let painter = evt.bc.painter
        let theme   = .getTheme()
        let colors  = .getThemeColors()
        let rects   = .getThemeRects()

        // Background bar
        if .barForm != .Transparent
        {
            var clientRect = .getClientRect()
            clientRect.height = .barHeight
            switch .barForm
            {
            case Flat:      painter.fillRect(clientRect, colors.tabBar_FlatBk)
            case FlatRound: theme.drawSubRect(painter, clientRect, &rects.tabBar_FlatRoundBk, colors.tabBar_FlatBk)
            case Round:     theme.drawSubRect(painter, clientRect, &rects.tabBar_RoundBk, colors.tabBar_RoundBk)
            }
        }

        // Paint border and back
        var subRect: #null *ThemeImageRect
        var colorBk: Color

        var clientRect = .getClientRect()
        clientRect.moveTop(.barHeight)
        switch .viewForm
        {
        case Flat:
            subRect = &rects.tabView_FlatBk
            colorBk = colors.tabView_FlatBk

        case Round:
            subRect = &rects.tabView_RoundBk
            colorBk = colors.tabView_RoundBk
        }

        theme.drawSubRect(painter, clientRect, subRect, colorBk)

        // Paint all except selected one, which will be painted last
        if !.views.isEmpty()
        {
            clientRect = .getBarRectItems()
            for [idx] in .firstVisibleIdx until cast(u32) .views.count
            {
                if idx == .selectedIdx do
                    continue
                let v = notnull .views[idx]
                if v.pos + v.width > clientRect.right() do
                    break
                .paintItem(painter, v, cast(u32) idx)
            }

            // Paint selected item
            .paintItem(painter, notnull .views[.selectedIdx], .selectedIdx)
        }
    }

    mtd impl onResizeEvent(evt: *ResizeEvent)
    {
        if .views.isEmpty() do
            return

        .computeTabLayout()
        .ensureVisible(.selectedIdx)

        let curView = (notnull .views[.selectedIdx]).view
        if curView
        {
            var clientRect = .getClientRect()
            clientRect.moveTop(.barHeight)
            clientRect.applyPadding(.padding)
            curView.setPosition(clientRect)
        }
    }

    mtd impl onMouseEvent(evt: *MouseEvent)
    {
        let hit = .hitTest(evt.surfacePos)
        if hit != .hotIdx
        {
            .hotIdx = hit
            .invalidate()
        }

        if hit == Swag.U32.Max
        {
            evt.accepted = false
            return
        }

        switch evt.kind
        {
        case .MouseLeave:
            if .hotIdx != Swag.U32.Max
            {
                .hotIdx = Swag.U32.Max
                .invalidate()
            }

        case .MousePressed:
            if evt.button == .Left
            {
                if hit != Swag.U32.Max
                {
                    .select(hit)
                }
            }
        }
    }
}

private impl Tab
{
    mtd showPopup(x, y: f32)
    {
        let popup = PopupListCtrl.create(me)
        .popup = popup
        for item in .views do
            popup.addItem((notnull item).name.raw, (notnull item).id, (notnull item).icon, (notnull item).userData0)

        popup.sigSelected = func|tab = me|(list, idx)
        {
            if idx != Swag.U32.Max do
                tab.select(idx)
            tab.hidePopup()
        }

        popup.show(x, y)
    }

    mtd hidePopup()
    {
        let popup = notnull .popup
        popup.destroy()
        .popup = null
    }

    mtd getBarRectItems()->Math.Rectangle
    {
        var rect = .getClientRectPadding()
        if .buttonPopup do
            rect.setRight(.buttonPopup.position.x - 4)
        return rect
    }

    mtd hitTest(surfacePos: Math.Point)->u32
    {
        let pos = .surfaceToLocal(surfacePos)
        if pos.y >= .barHeight do
            return Swag.U32.Max

        let rect = .getBarRectItems()
        for [idx] in .firstVisibleIdx until cast(u32) .views.count
        {
            let v = notnull .views[idx]
            if v.pos + v.width > rect.right() do
                break
            if pos.x >= v.pos and pos.x < v.pos + v.width do
                return cast() idx
        }

        return Swag.U32.Max
    }

    mtd computeTabLayout()
    {
        let rect = .getBarRectItems()

        .mostRightPos = rect.x
        switch .barLayout
        {
        case Divide:
            var w = cast(f32) (rect.width / .views.count)
            w = Math.max(w, .itemMinWidth)
            for vIt in .views
            {
                let v = notnull vIt
                v.width       = w
                .mostRightPos += w
            }

        case Fixed:
            let w = Math.max(.itemFixedLayoutWidth, .itemMinWidth)
            for vIt in .views
            {
                let v = notnull vIt
                v.width       = w
                .mostRightPos += w
            }

        case Auto:
            let font = nnFont(.getFont().regular)
            for vIt in .views
            {
                let v   = notnull vIt
                let mes = Painter.measureString(v.item.name.raw, font)

                // Text
                v.width = mes.width

                // Icon
                if v.item.icon.isValid() do
                    v.width += v.item.icon.sizeX + .getThemeMetrics().iconText_Margin

                // Margin
                v.width += .itemAutoLayoutMargin

                .mostRightPos += v.width
            }
        }

        var x = rect.x
        .mostRightPos = Math.round(rect.x)
        for [idx] in .firstVisibleIdx until cast(u32) .views.count
        {
            let v = notnull .views[idx]
            let left = Math.round(x)
            x += v.width
            let right = Math.round(x)
            v.pos         = left
            v.width       = Math.max(right - left, .itemMinWidth)
            .mostRightPos = right
        }

        .createDestroyButtonPopup()
    }

    mtd createDestroyButtonPopup()
    {
        let barRect = .getClientRectPadding()
        if .mostRightPos > barRect.right()
        {
            // Create a button if there are too many items for the given size
            if !.buttonPopup
            {
                let btnPopup = IconButton.create(me, .getTheme().getIcon24(ThemeIcons24.SortArrowDown), {})
                .buttonPopup       = btnPopup
                btnPopup.form       = .Round
                btnPopup.sigPressed += func|tab = me|(btn)
                {
                    var rect = btn.getSurfaceRect()
                    tab.showPopup(rect.x, rect.y + btn.position.height)
                }
            }

            let x  = barRect.right() - 32
            let bp = notnull .buttonPopup
            bp.setPosition({x, (.barHeight * 0.5) - 12, 24, 24})
        }
        elif .buttonPopup
        {
            .firstVisibleIdx = 0
            let bp = notnull .buttonPopup
            bp.destroy()
            .buttonPopup = null
            .computeTabLayout()
        }
    }

    mtd ensureVisible(idx: u32)
    {
        let rect = .getBarRectItems()
        if idx < .firstVisibleIdx or (notnull .views[idx]).pos + (notnull .views[idx]).width >= rect.right()
        {
            .firstVisibleIdx = idx
            var x = rect.right() - (notnull .views[.firstVisibleIdx]).width
            while .firstVisibleIdx
            {
                x -= (notnull .views[.firstVisibleIdx - 1]).width
                if x < rect.x do
                    break
                .firstVisibleIdx -= 1
            }

            .computeTabLayout()
        }
    }
}

impl Tab
{
    #[Swag.Discardable]
    func create(parent: *Wnd, position: Math.Rectangle = {}, id: #null WndId = null)->*Tab
    {
        Debug.assert(parent != null)
        let res = Wnd.create'Tab(parent, null, position, id)
        res.focusStrategy = .None
        res.setForm(.Flat)
        return res
    }

    // Set the tab form
    mtd setForm(tabForm: TabForm)
    {
        #[Swag.Complete]
        switch tabForm
        {
        case Flat:
            .barForm   = .Flat
            .itemForm  = .Flat
            .viewForm  = .Flat
            .barLayout = .Divide
            .barHeight = .getThemeMetrics().tabBar_FlatHeight

        case Round:
            .barForm   = .Transparent
            .itemForm  = .Round
            .viewForm  = .Round
            .barLayout = .Fixed
            .barHeight = .getThemeMetrics().tabBar_RoundHeight

        case Button:
            .viewForm  = .None
            .barForm   = .Round
            .itemForm  = .Button
            .barLayout = .Auto
            .barHeight = .getThemeMetrics().tabBar_ButtonHeight

        case PushButton:
            .viewForm  = .None
            .barForm   = .Transparent
            .itemForm  = .PushButton
            .barLayout = .Auto
            .barHeight = .getThemeMetrics().tabBar_ButtonHeight
        }
    }

    // Add a new view
    #[Swag.Discardable]
    mtd addItem(tabName: string, icon: Icon = {}, view: #null *Wnd = null)->*TabItem
    {
        if view
        {
            if .views.isEmpty() do
                view.wndFlags &= ~.Hidden
            else do
                view.wndFlags |= .Hidden
            view.setParent(me)
        }

        let item = .views.newPtr()
        item.view = view
        item.name = tabName
        item.icon = icon
        .views.add(item)

        .sendResizeEvent()
        return item
    }

    // Remove all items
    mtd clear()
    {
        .views.clear()
    }

    // Select one tab at the given index
    mtd select(idx: u32)
    {
        if .selectedIdx == idx or .selectedIdx >= .views.count do
            return

        let oldView = (notnull .views[.selectedIdx]).view
        if oldView do
            oldView.wndFlags |= .Hidden
        .selectedIdx = idx
        let newView = (notnull .views[.selectedIdx]).view
        if newView do
            newView.wndFlags &= ~.Hidden

        .sigSelChanged.call(me)

        .sendResizeEvent()
        .invalidate()
    }

    // Returns the current selected item, or 'null'
    mtd getSelectedItem()->#null *TabItem
    {
        Debug.assert(.selectedIdx < .views.count)
        return .views[.selectedIdx]
    }
}
