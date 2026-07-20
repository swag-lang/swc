#global public
using Core, Pixel

struct PopupListCtrlItem
{
    using base:      Item
    isSeparator:     bool
}

struct PopupListCtrl
{
    using frameWnd:       FrameWnd
    heightItem:           f32 = 30
    heightSeparator:      f32 = 15
    minWidthPopup:        f32 = 100
    maxHeightPopup:       f32 = 300
    simFitX, simFitY:     bool

    sigSelected:          func||(*PopupListCtrl, u32)

    items:                ArrayPtr'PopupListCtrlItem
    selectedIdx           = Swag.U32.Max
    scrollWnd:            *ScrollWnd
    maxIconSize:          s32
}

struct PopupListView
{
    using wnd:     Wnd
    list:          *PopupListCtrl
    hotIdx:        u32 = Swag.U32.Max
    closing:       bool
}

impl IWnd for PopupListView
{
    mtd impl onFocusEvent(evt: *FocusEvent)
    {
        switch evt.kind
        {
        case KillFocus:
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
        if evt.kind != .KeyPressed do
            return

        switch evt.key
        {
        case Up:
            .moveHot(-1)
        case Down:
            .moveHot(1)
        case Home:
            .moveHotEdge(forward: true)
        case End:
            .moveHotEdge(forward: false)
        case Return, Space:
            .close(.hotIdx)
        case Escape:
            .close(Swag.U32.Max)
        default:
            return
        }

        evt.accepted = true
    }

    mtd impl onMouseEvent(evt: *MouseEvent)
    {
        let mouseInRect = .getSurfaceRect().contains(evt.surfacePos)
        let pos         = .surfaceToLocal(evt.surfacePos)
        let hit         = mouseInRect ? .hitAt(pos) : Swag.U32.Max

        // The popup holds the mouse capture, so a MouseMove is delivered every frame
        // even when the cursor is still. Only let the mouse move the highlight when it
        // actually moves over the popup, otherwise a keyboard-driven highlight would
        // be wiped each frame.
        let mouseMoved = evt.move.x != 0 or evt.move.y != 0
        if evt.kind == .MouseMove and mouseMoved and mouseInRect and hit != .hotIdx
        {
            .hotIdx = hit
            .invalidate()
        }

        if evt.kind == .MousePressed and evt.button == .Left
        {
            // Click inside selects the item under the cursor; click outside cancels.
            if mouseInRect
            {
                .close(hit)
                return
            }

            if !.parent.getSurfaceRect().contains(evt.surfacePos)
            {
                .close(Swag.U32.Max)
                return
            }
        }

        evt.accepted = evt.kind == .MouseLeave
    }

    // Item index under a local position, or U32.Max when over a separator or empty
    // space.
    mtd hitAt(pos: Math.Point)->u32
    {
        var y = pos.y + .scrollPos.y
        for v, i in .list.items
        {
            let h = v.isSeparator ? .list.heightSeparator : .list.heightItem
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

    mtd impl onPaintEvent(evt: *PaintEvent)
    {
        let painter = evt.bc.painter

        let theme   = .getTheme()
        let colors  = .getThemeColors()
        let metrics = .getThemeMetrics()
        let rects   = .getThemeRects()

        var clientRect = .getClientRect()
        clientRect.offset(.scrollPos)

        var labelPos:  Math.Rectangle = undefined
        var colorText: Color

        var y = 0'f32
        for i, idx in .list.items
        {
            labelPos.x      = clientRect.x
            labelPos.y      = y
            labelPos.width  = clientRect.width
            labelPos.height = .list.heightItem

            var format: RichStringFormat
            colorText = colors.popupList_Text

            // Separator
            if i.isSeparator
            {
                labelPos.height = .list.heightSeparator
                painter.drawLine(labelPos.x + metrics.popupList_SeparatorPadding, labelPos.vertCenter(), labelPos.right() - metrics.popupList_SeparatorPadding, labelPos.vertCenter(), colors.popupList_Separator)
                y += .list.heightSeparator
                continue
            }

            // Back selection
            var colorSel:  Color
            var colorCheck = colors.popupList_CheckMark
            if .hotIdx == idx
            {
                colorSel   = colors.popupList_HotBk
                colorText  = colors.popupList_HotText
                colorCheck = colors.popupList_HotCheckMark
            }

            theme.drawSubRect(painter, labelPos, &rects.selectionBox_Bk, colorSel)
            labelPos.moveLeft(metrics.popupList_Padding)

            // Icon
            if i.icon.isValid()
            {
                let iconColor = i.icon.color.a ? i.icon.color : colorText
                i.icon.paint(painter, labelPos.x, labelPos.vertCenter() - i.icon.sizeY * 0.5, iconColor)
            }

            if .list.maxIconSize do
                labelPos.moveLeft(.list.maxIconSize + metrics.popupList_IconTextMargin)

            let fntHeight = .getFont().regular.height
            if idx == .list.selectedIdx do
                labelPos.setRight(labelPos.right() - fntHeight - metrics.popupList_IconTextMargin)

            // Text
            theme.setTextColors(&format, colorText)
            format.horzAlignment = .Left
            format.vertAlignment = .Center
            format.flags         = .Clip
            format.font          = .getFont()
            painter.drawRichString(labelPos, &i.name, format)

            // Check mark
            if idx == .list.selectedIdx
            {
                labelPos.x      = labelPos.right()
                labelPos.y      = labelPos.vertCenter() - (fntHeight * 0.5)
                labelPos.width  = fntHeight
                labelPos.height = fntHeight
                theme.drawSubRect(painter, labelPos, &rects.btnCheck_CheckedMark, colorCheck)
            }

            y += .list.heightItem
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

        if .getApp().mouseCaptureWnd == cast(*Wnd) me do
            .releaseMouse()

        if .list.sigSelected do
            .list.sigSelected(.list, idx)
        else do
            .list.destroy()
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
            if .list.selectedIdx < .list.items.count do
                idx = cast(s64) .list.selectedIdx
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
            if !.list.items[cast(u64) idx].isSeparator do
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
                if !v.isSeparator
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
                if !.list.items[cast(u64) i].isSeparator
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
    // Create the popup list, but: not display it
    func create(owner: #nonull *Wnd)->#nonull *PopupListCtrl
    {
        let popup = Wnd.create'PopupListCtrl(owner.getTopView(), owner.position, owner.id)

        with popup
        {
            .setFrameFlags(.SmallShadow)
            .setFrameForm(.Square)
            .scrollWnd               = .createView'ScrollWnd()
            .scrollWnd.dockStyle     = .Center
            .scrollWnd.focusStrategy = .None
            .scrollWnd.scrollWndFlags |= .SmallBar
            let popupView = .scrollWnd.createView'PopupListView()
            popupView.list = popup
        }

        return popup
    }

    // Keyboard control forwarded by a host that keeps the focus (e.g. the property
    // grid drives the popup while keeping its own navigation focus, so the keys
    // never leave the page).
    mtd keyMove(dir: s32)         { let view = cast(*PopupListView) .scrollWnd.view; view.moveHot(dir) }
    mtd keyHome()                 { let view = cast(*PopupListView) .scrollWnd.view; view.moveHotEdge(forward: true) }
    mtd keyEnd()                  { let view = cast(*PopupListView) .scrollWnd.view; view.moveHotEdge(forward: false) }
    mtd keyCancel()               { let view = cast(*PopupListView) .scrollWnd.view; view.close(Swag.U32.Max) }
    mtd keyCommit()
    {
        let view = cast(*PopupListView) .scrollWnd.view
        view.close(view.hotIdx)
    }

    // Show popup
    mtd show(x, y: f32, width: f32 = 10)
    {
        .scrollWnd.setScrollSize(0, cast(f32) .items.count * .heightItem)

        // Highlight the current selection as the keyboard starting point.
        let startView = cast(*PopupListView) .scrollWnd.view
        startView.hotIdx = .selectedIdx

        let pt  = .parent.surfaceToLocal({x, y})
        var pos = Math.Rectangle{pt.x, pt.y, 0, 0}
        pos.width  = Math.max(width, .minWidthPopup)
        pos.height = Math.min(.scrollWnd.scrollSize.y, .maxHeightPopup)
        pos.height += .padding.y + .padding.w
        .setPosition(pos)
        let sdw = .getThemeMetrics().frameWnd_SmallShadowSize
        .fitPosInParent(sdw.z, sdw.w, .simFitX, .simFitY)
        .scrollWnd.view.captureMouse()
    }

    // Add a new item in the list
    mtd addItem(name: #nonull string, id: #null WndId = null, icon: Icon = {}, userData0: #null *void = null, userData1: #null *void = null)
    {
        let item = .items.newPtr()
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
    }

    // Add a separator
    mtd addSeparator()
    {
        let item = .items.newPtr()
        item.isSeparator = true
        .items.add(item)
    }
}
