#global public

using Core, Pixel

// Stores one selectable item or separator in a popup list.
struct PopupListCtrlItem
{
    using base:  Item     // Embedded label, icon, identifier, and user data.
    isSeparator: bool     // Whether this entry separates groups and cannot be selected.
}

// Displays a temporary list that commits one highlighted item or reports cancellation.
struct PopupListCtrl
{
    using frameWnd: FrameWnd     // Embedded framed-window behavior and presentation.

    itemHeight:      f32 = 30      // Height of selectable rows in logical units.
    separatorHeight: f32 = 15      // Height of separator rows in logical units.
    minimumWidth:    f32 = 100     // Minimum popup width in logical units.
    maximumHeight:   f32 = 300     // Maximum popup height in logical units.
    fitHorizontally: bool          // Whether fitting may mirror horizontal placement around the owner.
    fitVertically:   bool          // Whether fitting may mirror vertical placement around the owner.

    // Emitted when the popup closes; the index is U32.Max when the action was canceled.
    sigClosed: #null func||(*PopupListCtrl, u32)

    readonly
    {
        items: ArrayPtr'PopupListCtrlItem     // Entries in display order.
        selectedIndex = Swag.U32.Max          // Initially highlighted item, or U32.Max.
        #[Swag.Late]
        scrollWnd: *ScrollWnd     // Scrollable viewport owned by the popup.
    }

    internal
    maxIconSize: s32     // Widest item icon, used to align labels.
}

// Implements painting and input inside a popup list.
internal struct PopupListView
{
    using wnd: Wnd     // Embedded wnd state.
    #[Swag.Late]
    list:    *PopupListCtrl         // List associated with this value.
    hotIdx:  u32 = Swag.U32.Max     // Index of hot.
    closing: bool                   // Closing associated with this value.
}

internal impl IWnd for PopupListView
{
    mtd impl onFocusEvent(evt: *FocusEvent)
    {
        switch evt.kind
        {
        case .Lost:

            // The focus left the popup (clicked elsewhere, another window, ...):
            // dismiss it.
            if !.closing and evt.other != .parent do
                .close(Swag.U32.Max)
        }
    }

    // Keyboard control of the popup when it holds the focus directly. The property
    // grid keeps the focus and forwards keys via PopupListCtrl.key* instead, but a
    // standalone focused popup still works through this path.
    mtd impl onKeyEvent(evt: *KeyEvent)
    {
        evt.accepted = false
        if evt.kind != .Pressed do
            return

        switch evt.key
        {
        case .Up:             .moveHot(-1)
        case .Down:           .moveHot(1)
        case .Home:           .moveHotEdge(forward: true)
        case .End:            .moveHotEdge(forward: false)
        case .Return, .Space: .close(.hotIdx)
        case .Escape:         .close(Swag.U32.Max)
        default:              return
        }

        evt.accepted = true
    }

    mtd impl onMouseEvent(evt: *MouseEvent)
    {
        let mouseInRect = .surfaceRect().contains(evt.surfacePos)
        let pos         = .surfaceToLocal(evt.surfacePos)
        let hit         = mouseInRect ? .hitAt(pos) : Swag.U32.Max

        // The popup holds the mouse capture, so a MouseMove is delivered every frame
        // even when the cursor is still. Only let the mouse move the highlight when it
        // actually moves over the popup, otherwise a keyboard-driven highlight would
        // be wiped each frame.
        let mouseMoved = evt.delta.x != 0 or evt.delta.y != 0
        if evt.kind == .Move and mouseMoved and mouseInRect and hit != .hotIdx
        {
            .hotIdx = hit
            .invalidate()
        }

        if evt.kind == .Pressed and evt.button == .Left
        {
            // Click inside selects the item under the cursor; click outside cancels.
            if mouseInRect
            {
                .close(hit)
                return
            }

            if !.parent!.surfaceRect().contains(evt.surfacePos)
            {
                .close(Swag.U32.Max)
                return
            }
        }

        evt.accepted = evt.kind == .Leave
    }

    // Item index under a local position, or U32.Max when over a separator or empty
    // space.
    mtd hitAt(pos: Math.Point)->u32
    {
        var y = pos.y + .scrollPos.y
        for vIt, [i] in .list.items
        {
            let v = notnull vIt
            let h = v.isSeparator ? .list.separatorHeight : .list.itemHeight
            if y <= h
            {
                if v.isSeparator do
                    return Swag.U32.Max
                return cast(u32) i
            }

            y -= h
        }

        return Swag.U32.Max
    }

    mtd impl onPaint(evt: *PaintEvent)
    {
        let painter = evt.paintContext.painter

        let theme   = .theme()
        let colors  = .themeColors()
        let metrics = .themeMetrics()
        let rects   = .themeRects()

        var clientRect = .clientRect()
        clientRect.offset(.scrollPos)

        var labelPos:  Math.Rectangle = undefined
        var colorText: Color

        var y = 0'f32
        for i, [idx] in .list.items
        {
            let it = notnull i
            labelPos.x      = clientRect.x
            labelPos.y      = y
            labelPos.width  = clientRect.width
            labelPos.height = .list.itemHeight

            var format: RichStringFormat
            colorText = colors.popupList_Text

            // Separator
            if it.isSeparator
            {
                labelPos.height = .list.separatorHeight
                painter.drawLine(labelPos.x + metrics.popupList_SeparatorPadding, labelPos.vertCenter(), labelPos.right() - metrics.popupList_SeparatorPadding, labelPos.vertCenter(), colors.popupList_Separator)
                y += .list.separatorHeight
                continue
            }

            // Back selection
            var colorSel: Color
            var colorCheck = colors.popupList_CheckMark
            let isHot      = .hotIdx == idx
            if isHot
            {
                colorSel   = colors.popupList_HotBk
                colorText  = colors.popupList_HotText
                colorCheck = colors.popupList_HotCheckMark
            }

            theme.drawSubRect(painter, labelPos, &rects.selectionBox_Bk, colorSel)
            if isHot and colors.activeRail.a
            {
                let rail = Math.Rectangle{labelPos.x, labelPos.y, 4, labelPos.height}
                painter.fillRect(rail, colors.activeRail)
            }

            labelPos.moveLeft(metrics.popupList_Padding)

            // Icon
            if it.icon.isValid()
            {
                let iconColor = it.icon.color.a ? it.icon.color : colorText
                it.icon.paint(painter, labelPos.x, labelPos.vertCenter() - it.icon.sizeY * 0.5, iconColor)
            }

            if .list.maxIconSize do
                labelPos.moveLeft(.list.maxIconSize + metrics.popupList_IconTextMargin)

            let fntHeight = (notnull .font().regular).height
            if idx == .list.selectedIndex do
                labelPos.setRight(labelPos.right() - fntHeight - metrics.popupList_IconTextMargin)

            // Text
            theme.setTextColors(&format, colorText)
            format.horzAlignment = .Left
            format.vertAlignment = .Center
            format.flags         = .Clip
            format.font          = .font()
            painter.drawRichString(labelPos, &it.name, format)

            // Check mark
            if idx == .list.selectedIndex
            {
                labelPos.x      = labelPos.right()
                labelPos.y      = labelPos.vertCenter() - (fntHeight * 0.5)
                labelPos.width  = fntHeight
                labelPos.height = fntHeight
                theme.drawSubRect(painter, labelPos, &rects.btnCheck_CheckedMark, colorCheck)
            }

            y += .list.itemHeight
        }
    }
}

private impl PopupListView
{
    // Close the popup, optionally committing the highlighted item.
    mtd close(idx: u32)
    {
        if .closing do
            return
        .closing = true

        if .app().mouseCaptureWnd == cast(*Wnd) me do
            .releaseMouse()

        let list = .list
        if list.sigClosed do
            list.sigClosed(list, idx)
        else do
            list.destroy()
    }

    // Move the highlight by 'dir' (+1/-1), skipping separators and clamping. Starts
    // from the current selection when nothing is highlighted yet.
    mtd moveHot(dir: s32)
    {
        if .list.items.isEmpty() do
            return

        var idx: s64
        if .hotIdx >= .list.items.count
        {
            if .list.selectedIndex < .list.items.count do
                idx = cast(s64) .list.selectedIndex
            else do
                idx = dir > 0 ? -1 : cast(s64) .list.items.count
        }
        else do
            idx = cast(s64) .hotIdx

        for
        {
            idx += dir
            if idx < 0 or idx >= cast(s64) .list.items.count do
                return
            if !(notnull .list.items[cast(u64) idx]).isSeparator do
                break
        }

        .hotIdx = cast(u32) idx
        .invalidate()
    }

    mtd moveHotEdge(forward: bool)
    {
        if forward
        {
            for v, [idx] in .list.items
            {
                if !v!.isSeparator
                {
                    .hotIdx = cast(u32) idx
                    .invalidate()
                    return
                }
            }
        }
        else
        {
            for var i = cast(s64) .list.items.count - 1; i >= 0; i -= 1
            {
                if !(notnull .list.items[cast(u64) i]).isSeparator
                {
                    .hotIdx = cast(u32) i
                    .invalidate()
                    return
                }
            }
        }
    }
}

impl PopupListCtrl
{
    // Creates a hidden popup list owned by the top view of `owner`.
    func create(owner: *Wnd)->*PopupListCtrl
    {
        let popup = Wnd.create'PopupListCtrl(owner.topView(), owner.position, owner.id)

        with popup
        {
            .setFrameFlags(.SmallShadow)
            .setFrameForm(.Square)
            .scrollWnd               = .createView'ScrollWnd()
            .scrollWnd.dockStyle     = .Center
            .scrollWnd.focusStrategy = .None
            .scrollWnd.updateFlags(.CompactBars)
            let popupView = .scrollWnd.createView'PopupListView()
            popupView.list = popup
        }

        return popup
    }

    // Moves the highlighted item by a signed distance, skipping separators.
    mtd moveHighlight(direction: s32)
    {
        let view = notnull cast(#null *PopupListView) .scrollWnd.view
        view.moveHot(direction)
    }

    // Highlights the first selectable item.
    mtd highlightFirst()
    {
        let view = notnull cast(#null *PopupListView) .scrollWnd.view
        view.moveHotEdge(forward: true)
    }

    // Highlights the last selectable item.
    mtd highlightLast()
    {
        let view = notnull cast(#null *PopupListView) .scrollWnd.view
        view.moveHotEdge(forward: false)
    }

    // Closes the popup and reports cancellation.
    mtd cancel()
    {
        let view = notnull cast(#null *PopupListView) .scrollWnd.view
        view.close(Swag.U32.Max)
    }

    // Closes the popup and commits the highlighted item, if any.
    mtd commitHighlighted()
    {
        let view = notnull cast(#null *PopupListView) .scrollWnd.view
        view.close(view.hotIdx)
    }

    // Shows the popup at the supplied surface coordinates and requested width.
    mtd show(x, y: f32, width: f32 = 10)
    {
        var contentHeight: f32
        for item in .items do
            contentHeight += item!.isSeparator ? .separatorHeight : .itemHeight
        .scrollWnd.setScrollSize(0, contentHeight)

        // Highlight the current selection as the keyboard starting point.
        let startView = notnull cast(#null *PopupListView) .scrollWnd.view
        startView.hotIdx = .selectedIndex

        let pt  = .parent!.surfaceToLocal({x, y})
        var pos = Math.Rectangle{pt.x, pt.y, 0, 0}
        pos.width  = Math.max(width, Math.max(.minimumWidth, 0))
        pos.height = Math.min(.scrollWnd.scrollSize.y, Math.max(.maximumHeight, 0))
        pos.height += .padding.y + .padding.w
        .setPosition(pos)
        let sdw = .themeMetrics().frameWnd_SmallShadowSize
        .fitPosInParent(sdw.z, sdw.w, .fitHorizontally, .fitVertically)
        .scrollWnd.view.captureMouse()
    }

    // Appends a selectable item and returns its stable heap object.
    #[Swag.Discardable]
    mtd addItem(name: string, id: #null WndId = null, icon: Icon = {}, userData0: #null *void = null, userData1: #null *void = null)->*PopupListCtrlItem
    {
        let item = .items.allocate()
        with item
        {
            .name      = name
            .icon      = icon
            .id        = id
            .userData0 = userData0
            .userData1 = userData1
        }

        if item.icon.isValid() do
            .maxIconSize = Math.max(.maxIconSize, cast(s32) item.icon.sizeX)
        .items.add(item)
        return item
    }

    // Appends a non-selectable separator and returns its stable heap object.
    #[Swag.Discardable]
    mtd addSeparator()->*PopupListCtrlItem
    {
        let item = .items.allocate()
        item.isSeparator = true
        .items.add(item)
        return item
    }

    // Sets the item highlighted when the popup opens, or clears it with U32.Max.
    mtd setSelectedIndex(index: u32)
    {
        Debug.assert(index == Swag.U32.Max or index < .items.count and !.items[index]!.isSeparator)
        .selectedIndex = index
    }
}
