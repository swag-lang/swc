#global public

using Core, Pixel

// Stores one selectable item or separator in a popup list.
struct PopupListCtrlItem
{
    public
    {
        using base:  Item     // Embedded label, icon, identifier, and user data.
        isSeparator: bool     // Whether this entry separates groups and cannot be selected.

        // Optional content painter, called inside this entry's selection ground instead of its
        // icon and wording. It receives Checked for the stored selection and Hot for the row
        // under the pointer, so a visual preset keeps the same interaction language as a text
        // entry without becoming a grid of buttons.
        contentPainter: #null func||(*PopupListCtrlItem, *PaintContext, Math.Rectangle, PaintItemFlags)
    }
}

// Displays a temporary list that commits one highlighted item or reports cancellation.
struct PopupListCtrl
{
    public
    {
        using frameWnd: FrameWnd     // Embedded framed-window behavior and presentation.

        itemHeight:      f32 = 24      // Height of selectable rows in logical units.
        iconSize:        f32 = 16      // Square size used for every item icon; zero uses each descriptor's own size.
        separatorHeight: f32 = 15      // Height of separator rows in logical units.
        minimumWidth:    f32 = 100     // Minimum popup width in logical units.
        maximumHeight:   f32 = 300     // Maximum popup height in logical units.
        fitHorizontally: bool          // Whether fitting may mirror horizontal placement around the owner.
        fitVertically:   bool          // Whether fitting may mirror vertical placement around the owner.

        // Leaves the check mark alone to say which entry is current, so the list opens with
        // nothing highlighted. Use it when the entries are painted samples rather than wording:
        // the opening highlight would put its accent ground behind one of them, and a sample of a
        // stroke drawn on that ground reads as a bar of colour instead of as the stroke it draws.
        markSelectionOnly: bool

        // Emitted when the popup closes; the index is U32.Max when the action was canceled.
        sigClosed: #null func||(*PopupListCtrl, u32)

        readonly
        {
            items: ArrayPtr'PopupListCtrlItem     // Entries in display order.
            selectedIndex = Swag.U32.Max          // Initially highlighted item, or U32.Max.
            #[Swag.Late]
            scrollWnd: *ScrollWnd     // Scrollable viewport owned by the popup.
        }
    }

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
        for vIt, i in .list.items
        {
            let v = vIt!
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

        var labelPos:  Math.Rectangle
        var colorText: Color

        var y = 0'f32
        for i, idx in .list.items
        {
            let it = i!
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
            var colorSel:   Color
            var colorCheck                 = colors.popupList_CheckMark
            let isHot                      = .hotIdx == idx
            var paintFlags: PaintItemFlags = .None
            if idx == .list.selectedIndex do
                paintFlags.add(.Checked)
            if isHot
            {
                colorSel   = colors.popupList_HotBk
                colorText  = colors.popupList_HotText
                colorCheck = colors.popupList_HotCheckMark
                paintFlags.add(.Hot)
            }

            theme.drawSubRect(painter, labelPos, &rects.selectionBox_Bk, colorSel)
            labelPos.moveLeft(metrics.popupList_Padding)

            // The mark leads the row, the way a menu marks a checked entry: it is found before
            // the content it qualifies rather than after crossing the whole row, and one rule
            // then covers every list the application opens.
            //
            // Its lane is kept on every row of a list that has a selection, so all of them start
            // at the same place — reserved on the marked row alone, that row was the one whose
            // wording ran out of room. And the lane is its own, in front of the icon rather than
            // over it: an icon here names the entry, where a menu's only decorates its command.
            let fntHeight = .font().regular!.height
            if .list.selectedIndex < .list.items.count
            {
                if idx == .list.selectedIndex
                {
                    var checkPos = labelPos
                    checkPos.y      = checkPos.vertCenter() - fntHeight * 0.5
                    checkPos.width  = fntHeight
                    checkPos.height = fntHeight
                    theme.drawSubRect(painter, checkPos, &rects.btnCheck_CheckedMark, colorCheck)
                }

                labelPos.moveLeft(fntHeight + metrics.popupList_IconTextMargin)
            }

            // Icon, plainly centered, because the entry beside it is centered on its capitals: a
            // drop-down shows the very entries the field above it shows, so the two have to place
            // them by the same rule or the list steps away from the field as it opens.
            if it.contentPainter
            {
                it.contentPainter(it, evt.paintContext, labelPos, paintFlags)
            }
            else
            {
                if it.icon.isValid()
                {
                    let iconColor = it.icon.color.a ? it.icon.color : colorText
                    var icon      = it.icon
                    if .list.iconSize != 0 do
                        icon.sizeX, icon.sizeY = .list.iconSize
                    icon.paint(painter, labelPos.x, labelPos.vertCenter() - icon.sizeY * 0.5, iconColor)
                }

                if .list.maxIconSize do
                    labelPos.moveLeft(.list.maxIconSize + metrics.popupList_IconTextMargin)

                // Text
                theme.setTextColors(&format, colorText)
                format.horzAlignment = .Left
                format.vertAlignment = .OpticalCenter
                format.flags         = .Clip
                format.font          = .font()
                painter.drawRichString(labelPos, &it.name, format)
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
            if !.list.items[cast(u64) idx]!.isSeparator do
                break
        }

        .hotIdx = cast(u32) idx
        .invalidate()
    }

    mtd moveHotEdge(forward: bool)
    {
        if forward
        {
            for v, idx in .list.items
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
                if !.list.items[cast(u64) i]!.isSeparator
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
            .scrollWnd           = .createView'ScrollWnd()
            .scrollWnd.dockStyle = .Center
            .scrollWnd.updateFlags(.CompactBars)
            let popupView = .scrollWnd.createView'PopupListView()
            popupView.list = popup
        }

        return popup
    }

    // Moves the highlighted item by a signed distance, skipping separators.
    mtd moveHighlight(direction: s32)
    {
        let view = cast(*PopupListView) .scrollWnd.view!
        view.moveHot(direction)
    }

    // Highlights the first selectable item.
    mtd highlightFirst()
    {
        let view = cast(*PopupListView) .scrollWnd.view!
        view.moveHotEdge(forward: true)
    }

    // Highlights the last selectable item.
    mtd highlightLast()
    {
        let view = cast(*PopupListView) .scrollWnd.view!
        view.moveHotEdge(forward: false)
    }

    // Closes the popup and reports cancellation.
    mtd cancel()
    {
        let view = cast(*PopupListView) .scrollWnd.view!
        view.close(Swag.U32.Max)
    }

    // Closes the popup and commits the highlighted item, if any.
    mtd commitHighlighted()
    {
        let view = cast(*PopupListView) .scrollWnd.view!
        view.close(view.hotIdx)
    }

    // Shows the popup at the supplied surface coordinates and requested width.
    mtd show(x, y: f32, width: f32 = 10)
    {
        var contentHeight: f32
        for item in .items do
            contentHeight += item!.isSeparator ? .separatorHeight : .itemHeight
        .scrollWnd.setScrollSize(0, contentHeight)

        // Highlight the current selection as the keyboard starting point. A list whose entries
        // are painted samples says which one is current with its check mark instead: filling that
        // row as well turns the sample into a bar of accent, which is the one thing a sample of a
        // stroke must not become. The keyboard still starts from the selection, which `moveHot`
        // reads on its own while nothing is highlighted.
        let startView = cast(*PopupListView) .scrollWnd.view!
        startView.hotIdx = .markSelectionOnly ? Swag.U32.Max : .selectedIndex

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

        if item.icon.isValid()
        {
            let iconWidth = .iconSize != 0 ? .iconSize : item.icon.sizeX
            .maxIconSize = Math.max(.maxIconSize, cast(s32) iconWidth)
        }

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
