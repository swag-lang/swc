#global public

using Core, Pixel

// Selects a coordinated tab bar, item, and page presentation.
enum TabForm
{
    Flat           // Uses flat tabs above a flat page frame.
    Round          // Uses rounded fixed-width tabs above a rounded page frame.
    Button         // Uses content-sized buttons without a page frame.
    PushButton     // Uses content-sized push buttons without a page frame.
}

// Selects tab bar background presentation.
enum TabBarForm
{
    Transparent     // Draws no bar background.
    Flat            // Draws a flat rectangular background.
    FlatRound       // Draws a flat background with rounded edges.
    Round           // Draws a rounded bar background.
}

// Selects individual tab presentation.
enum TabItemForm
{
    Transparent     // Draws labels without an item background.
    Flat            // Draws flat selection backgrounds.
    Round           // Draws rounded selection backgrounds.
    Button          // Draws compact button backgrounds.
    PushButton      // Draws bordered push-button backgrounds.
}

// Selects the selected page frame presentation.
enum TabViewForm
{
    None      // Draws no page background or border.
    Flat      // Draws a flat page background and border.
    Round     // Draws a rounded page background and border.
}

// Selects how tab widths are measured.
enum TabLayout
{
    Equal       // Divides available width equally, subject to the minimum width.
    Fixed       // Uses the configured fixed width for every tab.
    Content     // Sizes each tab from its label, icon, and item padding.
}

// Describes one tab label and its optional owned page view.
struct TabItem
{
    public
    {
        using item: Item     // Embedded label, icon, identifier, and user data.
        readonly
        view:       #null *Wnd     // Page view owned by the tab control, if any.
    }

    // Placement computed by the bar layout, and the color animations of the painted parts.
    pos:       f32            // Left edge of the tab in the bar.
    width:     f32            // Width of the tab in the bar.
    aniImg:    BlendColor     // Color animation of the icon.
    aniBorder: BlendColor     // Color animation of the border.
    aniText:   BlendColor     // Color animation of the label.
}

// Displays a selectable tab bar and one owned page view at a time.
struct Tab
{
    public
    {
        using wnd: Wnd     // Embedded window behavior and presentation.

        sigSelectionChanged: SigArray'func||(*Tab)     // Emitted after the selected tab changes.

        // The tabs the bar shows, in display order. Add and remove them through the methods, which
        // keep the views, the layout and the selection consistent.
        readonly
        {
            barForm:          TabBarForm  = .Flat            // Tab bar background presentation.
            itemForm:         TabItemForm = .Flat            // Individual tab presentation.
            viewForm:         TabViewForm = .Flat            // Selected page frame presentation.
            layout:           TabLayout   = .Equal           // Tab width measurement policy.
            fixedItemWidth:   f32         = 100              // Item width used by the fixed policy.
            itemPadding:      f32         = 25               // Extra width added by the content policy.
            minimumItemWidth: f32         = 25               // Minimum effective width for every tab.
            items:            ArrayPtr'TabItem               // Tabs in display order.
            selectedIndex                 = Swag.U32.Max     // Selected tab index, or U32.Max when empty.
            pageTransitions:  bool                           // Whether owned page changes use the standard transition.
        }
    }

    // Bar layout and overflow state, recomputed by the layout pass.
    buttonPopup:       #null *IconButton        // Button that opens the overflow list.
    popup:             #null *PopupListCtrl     // Overflow list while it is open.
    firstVisibleIndex: u32                      // First tab the bar can show.
    hotIndex:          u32 = Swag.U32.Max       // Tab under the mouse.
    barHeight:         f32                      // Height the bar measured for itself.
    mostRightPos:      f32                      // Right edge of the last laid out tab.
    selectionRail:     Math.Rectangle           // Animated active-rail position.
    hasSelectionRail:  bool                     // Whether the rail has been laid out once.
}

impl IWnd for Tab
{
    mtd paintItem(painter: *Painter, v: *TabItem, idx: u32)
    {
        var clientRect = .clientRect()
        clientRect.height = Math.min(.barHeight, clientRect.height)

        var labelPos = clientRect
        labelPos.width = v.width
        labelPos.x     = v.pos

        let theme   = .theme()
        let metrics = .themeMetrics()
        let colors  = .themeColors()
        let rects   = .themeRects()

        // Item image
        var subRect:       #null *ThemeImageRect
        var subRectBorder: #null *ThemeImageRect
        var colorImg:      Color
        var colorText:     Color
        var colorBorder:   Color

        // A tab says it is the selected one exactly once, in the vocabulary of its own form. A
        // round, button or push-button tab is a shape, and the shape carries the state; the
        // accent rule drawn across it as well cuts through the form and reports the same thing
        // twice. Only a tab with no shape of its own is marked by the rule — and there the rule
        // takes the place of the neutral underline instead of stacking a second bar under it.
        let railed = colors.activeRail.a != 0 and (.itemForm == .Flat or .itemForm == .Transparent)

        switch #complete .itemForm
        {
        case .Flat:
            if idx == .selectedIndex
            {
                if !railed
                {
                    subRect  = &rects.tabItem_FlatSelected
                    colorImg = colors.tabItem_FlatSelected
                }

                colorText = colors.tabItem_SelectedText
            }
            elif idx == .hotIndex
            {
                subRect   = &rects.tabItem_FlatSelected
                colorImg  = colors.tabItem_FlatHot
                colorText = colors.tabItem_HotText
            }
            else
            {
                colorText = colors.tabItem_Text
            }

        case .Round:
            if idx == .selectedIndex
            {
                subRect   = &rects.tabItem_RoundSelected
                colorImg  = colors.tabItem_RoundSelected
                colorText = colors.tabItem_SelectedText
            }
            elif idx == .hotIndex
            {
                subRect   = &rects.tabItem_RoundHot
                colorImg  = colors.tabItem_RoundHot
                colorText = colors.tabItem_HotText
            }
            else
            {
                colorText = colors.tabItem_Text
            }

        case .Button:
            if idx == .selectedIndex
            {
                subRect   = &rects.tabItem_ButtonSelected
                colorImg  = colors.tabItem_ButtonSelected
                colorText = colors.tabItem_SelectedText
            }
            elif idx == .hotIndex
            {
                subRect   = &rects.tabItem_ButtonHot
                colorImg  = colors.tabItem_ButtonHot
                colorText = colors.tabItem_HotText
            }
            else
            {
                colorText = colors.tabItem_Text
            }

        case .PushButton:
            if idx == .selectedIndex
            {
                subRect       = &rects.tabItem_PushButtonSelected
                subRectBorder = &rects.tabItem_PushButtonBorder
                colorImg      = colors.tabItem_PushButtonSelected
                colorText     = colors.tabItem_PushButtonSelectedText
                colorBorder   = colors.tabItem_PushButtonSelectedBorder
            }
            elif idx == .hotIndex
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

        // A transparent tab draws no ground at all, so the wording is the only thing that can
        // report the state. It still has to be drawn: left to the default it was written in a
        // transparent ink and the bar came out empty.
        case .Transparent:
            if idx == .selectedIndex do
                colorText = colors.tabItem_SelectedText
            elif idx == .hotIndex do
                colorText = colors.tabItem_HotText
            else do
                colorText = colors.tabItem_Text
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
        format.font          = .font()
        Theme.drawIconText(painter, labelPos, v.icon, &v.name, format, metrics.iconText_Margin)

        // The keyboard stands on one tab, not on the whole control: a ring around the control
        // would enclose the page it shows, so the selected tab carries it. A form that grounds
        // its tab lends the ring that ground's corner; a flat or transparent bar has none, and
        // the ring keeps its own.
        if idx == .selectedIndex and .showsFocusRing()
        {
            var ringGround: Color
            var ringCorner = 0'f32
            if subRect
            {
                ringCorner = subRect!.radius
                ringGround = v.aniImg.cur()
            }

            theme.drawFocusRing(painter, labelPos, ringCorner, ringGround)
        }
    }

    mtd impl onPaint(evt: *PaintEvent)
    {
        let painter = evt.paintContext.painter
        let theme   = .theme()
        let colors  = .themeColors()
        let rects   = .themeRects()

        // Background bar
        if .barForm != .Transparent
        {
            var clientRect = .clientRect()
            clientRect.height = .barHeight
            switch .barForm
            {
            case .Flat:      painter.fillRect(clientRect, colors.tabBar_FlatBk)
            case .FlatRound: theme.drawSubRect(painter, clientRect, &rects.tabBar_FlatRoundBk, colors.tabBar_FlatBk)
            case .Round:     theme.drawSubRect(painter, clientRect, &rects.tabBar_RoundBk, colors.tabBar_RoundBk)
            }
        }

        // Paint border and back
        var subRect: #null *ThemeImageRect
        var colorBk: Color

        var clientRect = .clientRect()
        clientRect.moveTop(.barHeight)
        switch .viewForm
        {
        case .Flat:
            subRect = &rects.tabView_FlatBk
            colorBk = colors.tabView_FlatBk

        case .Round:
            subRect = &rects.tabView_RoundBk
            colorBk = colors.tabView_RoundBk
        }

        theme.drawSubRect(painter, clientRect, subRect, colorBk)

        // Paint all except selected one, which will be painted last
        if !.items.isEmpty()
        {
            clientRect = .itemBarRect()
            for idx in .firstVisibleIndex until cast(u32) .items.count
            {
                if idx == .selectedIndex do
                    continue
                let v = .items[idx]!
                if v.pos + v.width > clientRect.right() do
                    break
                .paintItem(painter, v, cast(u32) idx)
            }

            // Paint selected item
            .paintItem(painter, .items[.selectedIndex]!, .selectedIndex)

            let railed = colors.activeRail.a != 0 and (.itemForm == .Flat or .itemForm == .Transparent)
            if railed and .hasSelectionRail do
                painter.fillRect(.selectionRail, colors.activeRail)
        }
    }

    mtd impl onResizeEvent(evt: *ResizeEvent)
    {
        if .items.isEmpty() do
            return

        .computeTabLayout()
        .ensureVisible(.selectedIndex)

        let railChannel = AnimationChannel.from("Gui.Tab.SelectionRail")
        if !.app().animator.isActive(me, railChannel)
        {
            .selectionRail    = .selectionRailRect(.selectedIndex)
            .hasSelectionRail = true
        }

        let curView = .items[.selectedIndex]!.view
        if curView
        {
            var clientRect = .clientRect()
            clientRect.moveTop(.barHeight)
            clientRect.applyPadding(.padding)
            curView.setPosition(clientRect)
        }
    }

    mtd impl onMouseEvent(evt: *MouseEvent)
    {
        let hit = .hitTest(evt.surfacePos)
        if hit != .hotIndex
        {
            .hotIndex = hit
            .invalidate()
        }

        if hit == Swag.U32.Max
        {
            evt.accepted = false
            return
        }

        switch evt.kind
        {
        case .Leave:
            if .hotIndex != Swag.U32.Max
            {
                .hotIndex = Swag.U32.Max
                .invalidate()
            }

        case .Pressed:
            if evt.button == .Left
            {
                if hit != Swag.U32.Max
                {
                    .setSelectedIndex(hit)
                }
            }
        }
    }

    // Arrow keys move between adjacent tabs; Home and End select the edges.
    mtd impl onKeyEvent(evt: *KeyEvent)
    {
        evt.accepted = false
        if evt.kind != .Pressed or .items.isEmpty() do
            return

        var index = .selectedIndex
        switch evt.key
        {
        case .Left, .Up:
            if index > 0 do
                index -= 1

        case .Right, .Down:
            if index + 1 < .items.count do
                index += 1

        case .Home:
            index = 0

        case .End:
            index = cast(u32) .items.count - 1

        default:
            return
        }

        .setSelectedIndex(index)
        evt.accepted = true
    }
}

private impl Tab
{
    mtd showPopup(x, y: f32)
    {
        let popup = PopupListCtrl.create(me)
        .popup = popup
        for item in .items do
            popup.addItem(item!.name.raw, item!.id, item!.icon, item!.userData0)
        if .selectedIndex < .items.count do
            popup.setSelectedIndex(.selectedIndex)

        popup.sigClosed = func|tab = me|(list, idx)
        {
            if idx != Swag.U32.Max do
                tab.setSelectedIndex(idx)
            tab.hidePopup()
        }

        popup.show(x, y)
    }

    mtd hidePopup()
    {
        let popup = .popup!
        popup.destroy()
        .popup = null
    }

    mtd itemBarRect()->Math.Rectangle
    {
        var rect = .paddedClientRect()
        if .buttonPopup do
            rect.setRight(.buttonPopup.position.x - .themeMetrics().tabBar_PopupButtonMargin)
        return rect
    }

    mtd selectionRailRect(index: u32)->Math.Rectangle
    {
        let item    = .items[index]!
        let metrics = .themeMetrics()
        let size    = metrics.activeRail_Size
        var rail    = Math.Rectangle{item.pos, .barHeight - size, item.width, size}
        rail.inflate(-Math.min(metrics.activeRail_Margin, rail.width / 3), 0)
        return rail
    }

    mtd hitTest(surfacePos: Math.Point)->u32
    {
        let pos = .surfaceToLocal(surfacePos)
        if pos.y >= .barHeight do
            return Swag.U32.Max

        let rect = .itemBarRect()
        for idx in .firstVisibleIndex until cast(u32) .items.count
        {
            let v = .items[idx]!
            if v.pos + v.width > rect.right() do
                break
            if pos.x >= v.pos and pos.x < v.pos + v.width do
                return cast() idx
        }

        return Swag.U32.Max
    }

    // Returns the width one tab needs for its label, its optional icon, and the item padding.
    mtd itemContentWidth(v: *TabItem)->f32
    {
        let font   = nnFont(.font().regular)
        var result = Painter.measureString(v.item.name.raw, font).width
        if v.item.icon.isValid() do
            result += v.item.icon.sizeX + .themeMetrics().iconText_Margin
        return result + .itemPadding
    }

    // Returns the width every tab needs side by side under the content policy.
    mtd contentWidth()->f32
    {
        var result = 0'f32
        for v in .items do
            result += Math.max(.itemContentWidth(v!), .minimumItemWidth)
        return result
    }

    // Reports the room every tab needs side by side, and the height of the bar.
    //
    // Only the content policy answers with the wording: the equal and fixed policies decide
    // a width themselves, so what they need is that width once per tab. The height is the
    // bar alone — the page below it is measured by whatever the tab hosts.
    mtd impl measureContent(available: Math.Point)->Math.Point
    {
        discard available

        var width = 0'f32
        switch .layout
        {
        case .Equal:   width = Math.max(.minimumItemWidth, 0) * cast(f32) .items.count
        case .Fixed:   width = Math.max(.fixedItemWidth, .minimumItemWidth) * cast(f32) .items.count
        case .Content: width = .contentWidth()
        }

        let padding = .padding
        return {width + padding.x + padding.z, .barHeight + padding.y + padding.w}
    }

    mtd computeTabLayout()
    {
        let rect = .itemBarRect()

        .mostRightPos = rect.x
        switch .layout
        {
        case .Equal:
            var w = cast(f32) (rect.width / .items.count)
            w = Math.max(w, .minimumItemWidth)
            for vIt in .items
            {
                let v = vIt!
                v.width       = w
                .mostRightPos += w
            }

        case .Fixed:
            let w = Math.max(.fixedItemWidth, .minimumItemWidth)
            for vIt in .items
            {
                let v = vIt!
                v.width       = w
                .mostRightPos += w
            }

        case .Content:
            for vIt in .items
            {
                let v = vIt!
                v.width       = .itemContentWidth(v)
                .mostRightPos += v.width
            }
        }

        var x = rect.x
        .mostRightPos = Math.round(rect.x)
        for idx in .firstVisibleIndex until cast(u32) .items.count
        {
            let v    = .items[idx]!
            let left = Math.round(x)
            x += v.width
            let right = Math.round(x)
            v.pos         = left
            v.width       = Math.max(right - left, .minimumItemWidth)
            .mostRightPos = right
        }

        .createDestroyButtonPopup()
    }

    mtd createDestroyButtonPopup()
    {
        let barRect = .paddedClientRect()
        let metrics = .themeMetrics()
        if .mostRightPos > barRect.right()
        {
            // Create a button if there are too many items for the given size
            if !.buttonPopup
            {
                let btnPopup = IconButton.create(me, .theme().icon(ThemeIcons.ChevronDown, metrics.tabBar_PopupButtonGlyph), {})
                .buttonPopup = btnPopup
                btnPopup.setForm(.Circle)
                btnPopup.sigPressed += func|tab = me|(btn)
                {
                    var rect = btn.surfaceRect()
                    tab.showPopup(rect.x, rect.y + btn.position.height)
                }
            }

            let size = metrics.tabBar_PopupButtonSize
            let bp   = .buttonPopup!
            bp.setPosition({barRect.right() - size - metrics.tabBar_PopupButtonMargin, (.barHeight - size) * 0.5, size, size})
        }
        elif .buttonPopup
        {
            .firstVisibleIndex = 0
            let bp = .buttonPopup!
            bp.destroy()
            .buttonPopup = null
            .computeTabLayout()
        }
    }

    mtd ensureVisible(idx: u32)
    {
        let rect = .itemBarRect()
        if idx < .firstVisibleIndex or .items[idx]!.pos + .items[idx]!.width >= rect.right()
        {
            .firstVisibleIndex = idx
            var x = rect.right() - .items[.firstVisibleIndex]!.width
            while .firstVisibleIndex
            {
                x -= .items[.firstVisibleIndex - 1]!.width
                if x < rect.x do
                    break
                .firstVisibleIndex -= 1
            }

            .computeTabLayout()
        }
    }
}

impl Tab
{
    // Creates an empty, keyboard-focusable tab control.
    #[Swag.Discardable]
    func create(parent: *Wnd, position: Math.Rectangle = {}, id: #null WndId = null)->*Tab
    {
        Debug.assert(parent != null)
        let result = Wnd.create'Tab(parent, null, position, id)
        result.focusPolicy = .Tab
        result.wndFlags    |= .NoFocusRing
        result.setForm(.Flat)
        return result
    }

    // Applies a coordinated predefined presentation and width policy.
    mtd setForm(form: TabForm)
    {
        switch #complete form
        {
        case .Flat:
            .barForm   = .Flat
            .itemForm  = .Flat
            .viewForm  = .Flat
            .layout    = .Equal
            .barHeight = .themeMetrics().tabBar_FlatHeight

        case .Round:
            .barForm   = .Transparent
            .itemForm  = .Round
            .viewForm  = .Round
            .layout    = .Fixed
            .barHeight = .themeMetrics().tabBar_RoundHeight

        case .Button:
            .viewForm  = .None
            .barForm   = .Round
            .itemForm  = .Button
            .layout    = .Content
            .barHeight = .themeMetrics().tabBar_ButtonHeight

        case .PushButton:
            .viewForm  = .None
            .barForm   = .Transparent
            .itemForm  = .PushButton
            .layout    = .Content
            .barHeight = .themeMetrics().tabBar_ButtonHeight
        }

        .sendResizeEvent()
        .invalidate()
    }

    // Replaces the bar, item, and selected-page presentation independently.
    mtd setForms(bar: TabBarForm, item: TabItemForm, view: TabViewForm)
    {
        .barForm  = bar
        .itemForm = item
        .viewForm = view
        .sendResizeEvent()
        .invalidate()
    }

    // Configures width measurement and validates non-negative sizing values.
    mtd setLayout(layout: TabLayout, minimumItemWidth = 25'f32, fixedItemWidth = 100'f32, itemPadding = 25'f32)
    {
        Debug.assert(minimumItemWidth >= 0)
        Debug.assert(fixedItemWidth >= 0)
        Debug.assert(itemPadding >= 0)
        .layout           = layout
        .minimumItemWidth = minimumItemWidth
        .fixedItemWidth   = fixedItemWidth
        .itemPadding      = itemPadding
        .sendResizeEvent()
        .invalidate()
    }

    // Enables or disables the standard covered cross-fade-and-arrival transition between owned pages.
    mtd setPageTransitions(enabled: bool)
    {
        .pageTransitions = enabled
        if !enabled and .selectedIndex < .items.count
        {
            let view = .items[.selectedIndex]!.view
            if view
            {
                .app().animator.cancel(view!, AnimationChannel.from("Gui.Page.Opacity"))
                view.resetPresentation()
            }
        }
    }

    // Appends a tab and transfers ownership of its optional page view to this control.
    #[Swag.Discardable]
    mtd addItem(name: string, icon: Icon = {}, view: #null *Wnd = null)->*TabItem
    {
        let isFirst = .items.isEmpty()
        if view
        {
            if isFirst do
                view.wndFlags &= ~.Hidden
            else do
                view.wndFlags |= .Hidden
            view.setParent(me)
        }

        let item = .items.allocate()
        item.view = view
        item.name = name
        item.icon = icon
        .items.add(item)
        if isFirst do
            .selectedIndex = 0

        .sendResizeEvent()
        .invalidate()
        return item
    }

    // Replaces the label of one tab and measures the bar again around the new wording.
    //
    // A language switch is what needs this. Under the `Content` policy a tab is exactly as wide as
    // its label, so a renamed tab that is not measured again keeps the width of the wording it no
    // longer shows — and the strip either clips the new label or leaves a gap where the old one
    // ended.
    mtd setItemName(index: u32, name: string)
    {
        Debug.assert(index < .items.count)
        .items[index]!.name = name
        .sendResizeEvent()
        .invalidate()
    }

    // Removes one tab, destroys its owned page, and selects the nearest remaining tab.
    mtd removeItemAt(index: u32)
    {
        Debug.assert(index < .items.count)
        .closePopups()
        .app().animator.cancel(me, AnimationChannel.from("Gui.Tab.SelectionRail"))

        let wasSelected = .selectedIndex == index
        let view        = .items[index]!.view
        if view do
            view.destroy()
        .items.deleteAt(index)

        if .items.isEmpty()
        {
            .selectedIndex     = Swag.U32.Max
            .firstVisibleIndex = 0
        }
        elif .selectedIndex > index
        {
            .selectedIndex -= 1
        }
        elif wasSelected
        {
            .selectedIndex = Math.min(index, cast(u32) .items.count - 1)
            let selectedView = .items[.selectedIndex]!.view
            if selectedView do
                selectedView.wndFlags &= ~.Hidden
            .sigSelectionChanged.call(me)
        }

        .sendResizeEvent()
        .invalidate()
    }

    // Removes all tabs and destroys every page view previously transferred to the control.
    mtd clear()
    {
        .closePopups()
        for item in .items
        {
            let view = item!.view
            if view do
                view.destroy()
        }

        .items.clear()
        .selectedIndex     = Swag.U32.Max
        .firstVisibleIndex = 0
        .hasSelectionRail  = false
        .app().animator.cancel(me, AnimationChannel.from("Gui.Tab.SelectionRail"))
        .sendResizeEvent()
        .invalidate()
    }

    // Selects one tab and emits a change signal when the effective item changes.
    mtd setSelectedIndex(index: u32)
    {
        Debug.assert(index < .items.count)
        if .selectedIndex == index do
            return

        let oldIndex = .selectedIndex
        var oldView: #null *Wnd
        if oldIndex < .items.count do
            oldView = .items[oldIndex]!.view

        .selectedIndex = index
        let newView = .items[.selectedIndex]!.view
        if .pageTransitions and newView
        {
            let direction = oldIndex < index ? 1'f32 : -1'f32
            discard .app().animator.transitionPage(oldView, newView!, direction)
        }
        else
        {
            if oldView do
                oldView.hide()
            if newView do
                newView.show()
        }

        .ensureVisible(index)
        let destination = .selectionRailRect(index)
        if !.hasSelectionRail
        {
            .selectionRail    = oldIndex < .items.count ? .selectionRailRect(oldIndex) : destination
            .hasSelectionRail = true
        }

        var options: AnimationOptions
        options.duration = Time.Duration.fromSeconds(.themeMetrics().motion_QuickSeconds)
        options.easing   = .EaseOut
        discard .app().animator.animateRectangle(me,
                                                 AnimationChannel.from("Gui.Tab.SelectionRail"),
                                                 .selectionRail,
                                                 destination,
                                                 func|tab=me|(animationWnd, value)
                                                 {
                                                     discard animationWnd
                                                     tab.selectionRail = value
                                                 },
                                                 options)

        .sigSelectionChanged.call(me)

        .sendResizeEvent()
        .invalidate()
    }

    // Returns the selected item, or null when the control is empty.
    mtd const selectedItem()->#null *TabItem
    {
        if .selectedIndex >= .items.count do
            return null
        return .items[.selectedIndex]
    }
}

private impl Tab
{
    mtd closePopups()
    {
        if .popup do
            .hidePopup()
        if .buttonPopup
        {
            let button = .buttonPopup!
            button.destroy()
            .buttonPopup = null
        }
    }
}
