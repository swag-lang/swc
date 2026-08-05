#global public

using Core, Pixel

// Configures splitter orientation and divider painting.
#[Swag.EnumFlags]
enum SplitterFlags
{
    None = 0         // Arranges panes horizontally and paints dividers.
    Vertical         // Arranges panes vertically.
    HideDividers     // Hides idle dividers while preserving drag interaction.
}

// Configures one pane managed by a [[SplitterCtrl]].
struct SplitterItem
{
    #[Swag.Late]
    view:         *Wnd             // Pane content window.
    size:         f32              // Current size along the splitting axis.
    minimumSize:  f32 = 5          // Minimum size along the splitting axis.
    maximumSize:  f32 = 0          // Maximum size, or zero for no upper bound.
    label:        #null *Label     // Optional pane title managed by the splitter.
    preserveSize: bool             // Whether other panes absorb resize changes first.
    internal
    visible = true     // Whether the pane participates in layout.

    // Color animation of the bar that follows this pane.
    internal
    aniBar: BlendColor
}

// Arranges resizable panes separated by draggable dividers.
struct SplitterCtrl
{
    using frameWnd: FrameWnd                     // Embedded frame wnd state.
    flags               = SplitterFlags.None     // Orientation and divider options.
    titleSize:      f32 = 30                     // Title extent along the splitting axis.

    // The panes the splitter manages, in order. Add them through the methods so the bars and
    // the layout follow.
    readonly
    items: ArrayPtr'SplitterItem

    // Hover and drag state of one gesture over a bar, and the pane count the layout derived.
    internal
    {
        correctMoving:   f32      // Grab offset inside the bar, kept for the drag.
        hotIdx = Swag.U32.Max     // Bar under the mouse.
        moving:          bool     // Whether a bar drag is in progress.
        numVisiblePanes: s32      // Panes the last layout actually placed.
    }
}

impl IWnd for SplitterCtrl
{
    mtd impl onMouseEvent(evt: *MouseEvent)
    {
        evt.accepted = true
        let local = .surfaceToLocal(evt.surfacePos)

        switch evt.kind
        {
        case .Leave:
            if .hotIdx != Swag.U32.Max
            {
                .hotIdx = Swag.U32.Max
                .invalidate()
            }

        case .Move:
            if .moving
            {
                let rect = .barRectAt(.hotIdx)
                if .isVertical()
                {
                    let diff = local.y - (rect.y + .correctMoving)
                    .setPaneSize(.hotIdx, .items[.hotIdx]!.size + diff)
                }
                else
                {
                    let diff = local.x - (rect.x + .correctMoving)
                    .setPaneSize(.hotIdx, .items[.hotIdx]!.size + diff)
                }

                .invalidate()
            }
            else
            {
                let newHot = .hitTest(evt.surfacePos)
                if newHot != .hotIdx do
                    .invalidate()
                .hotIdx = newHot
            }

        case .Pressed:
            if evt.button == .Left and .hotIdx != Swag.U32.Max
            {
                let rect = .barRectAt(.hotIdx)
                .moving = true
                let srf = .surface!
                srf.app.captureMouse(me)
                if .isVertical() do
                    .correctMoving = local.y - rect.y
                else do
                    .correctMoving = local.x - rect.x
            }

        case .Released:
            if .moving
            {
                .moving = false
                let srf = .surface!
                srf.app.releaseMouse()
            }
        }

        if .hotIdx != Swag.U32.Max do
            .cursor = .isVertical() ? Cursor.from(CursorShape.ResizeVertical) : Cursor.from(CursorShape.ResizeHorizontal)
        else do
            .cursor.clear()
    }

    mtd impl onResizeEvent(evt: *ResizeEvent)
    {
        .computeLayout()

        let client  = .paddedClientRect()
        var x       = client.x
        var y       = client.y
        let barSize = .themeMetrics().splitView_BarSize

        for item in .items
        {
            let it = item!
            if !it.visible do
                continue

            if .isVertical()
            {
                var paneRect = Math.Rectangle{client.x, y, client.width, it.size}
                paneRect.applyPadding(it.view.margin)

                if it.label
                {
                    var labelRect = paneRect
                    labelRect.height = .titleSize
                    it.label.setPosition(labelRect)

                    paneRect.y      += .titleSize
                    paneRect.height -= .titleSize
                }

                it.view.setPosition(paneRect)
                y += it.size + barSize
            }
            else
            {
                var paneRect = Math.Rectangle{x, client.y, it.size, client.height}
                paneRect.applyPadding(it.view.margin)

                if it.label
                {
                    var labelRect = paneRect
                    labelRect.width = .titleSize
                    it.label.setPosition(labelRect)

                    paneRect.x     += .titleSize
                    paneRect.width -= .titleSize
                }

                it.view.setPosition(paneRect)
                x += it.size + barSize
            }
        }
    }

    mtd impl onAfterPaint(evt: *PaintEvent)
    {
        if !.items.count do
            return

        let painter = evt.paintContext.painter
        let theme   = .theme()
        let rects   = .themeRects()
        let colors  = .themeColors()

        var visibleIndex = 0
        for item, [idx] in .items
        {
            let it = item!
            if !it.visible do
                continue
            visibleIndex += 1
            if visibleIndex == .numVisiblePanes do
                break

            let rect  = .barRectAt(cast(u32) idx)
            let isHot = .hotIdx == idx
            if isHot or !.flags.has(.HideDividers)
            {
                let colorBar = isHot ? colors.splitView_BarHot : colors.splitView_Bar
                it.aniBar.apply(me, colorBar)
                if .isVertical()
                {
                    let rectBar = isHot ? &rects.splitView_HorzBarHotBk : &rects.splitView_HorzBarBk
                    theme.drawSubRect(painter, rect, rectBar, it.aniBar.cur())
                }
                else
                {
                    let rectBar = isHot ? &rects.splitView_VertBarHotBk : &rects.splitView_VertBarBk
                    theme.drawSubRect(painter, rect, rectBar, it.aniBar.cur())
                }
            }
        }

        .frameWnd.IWnd.onAfterPaint(evt)
    }
}

private impl SplitterCtrl
{
    mtd computeLayout()
    {
        let rect = .paddedClientRect()
        if .numVisiblePanes <= 0 do
            return
        let available = .isVertical() ? rect.height : rect.width
        if available <= .numVisiblePanes do
            return

        let barSize = .themeMetrics().splitView_BarSize

        var dispatch: f32
        if !.items.isEmpty()
        {
            // Compute the current total sizes of panes
            var countNotPreserve, countPreserve = 0
            var totalSize                       = 0'f32
            for item, [idx] in .items
            {
                let it = item!
                if !it.visible do
                    continue

                totalSize        += it.size
                countPreserve    += it.preserveSize ? 1 : 0
                countNotPreserve += it.preserveSize ? 0 : 1
            }

            totalSize += cast(f32) ((.numVisiblePanes - 1) * barSize)

            // Compute the size to adapt
            if .isVertical() do
                dispatch = cast(f32) (rect.height - totalSize)
            else do
                dispatch = cast(f32) (rect.width - totalSize)

            // Dispatch the size change first to all panes not marked as 'tryPreserveSize'
            if countNotPreserve
            {
                let diff = cast(f32) Math.round(dispatch / countNotPreserve)
                for item, [idx] in .items
                {
                    let it = item!
                    if it.preserveSize do
                        continue
                    if !it.visible do
                        continue

                    countNotPreserve -= 1

                    var realDiff = countPreserve ? diff : dispatch
                    if it.maximumSize > 0 and realDiff > 0 and it.size + realDiff > it.maximumSize do
                        realDiff = it.maximumSize - it.size
                    elif realDiff < 0 and it.size + realDiff < it.minimumSize do
                        realDiff = it.minimumSize - it.size

                    it.size  += realDiff
                    dispatch -= realDiff
                }
            }

            // Dispatch the rest between panes that try to preserved their size
            if countPreserve
            {
                let diff = cast(f32) Math.round(dispatch / countPreserve)
                for item, [idx] in .items
                {
                    let it = item!
                    if !it.preserveSize do
                        continue
                    if !it.visible do
                        continue

                    countPreserve -= 1

                    var realDiff = countNotPreserve ? diff : dispatch
                    if it.maximumSize > 0 and realDiff > 0 and it.size + realDiff > it.maximumSize do
                        realDiff = it.maximumSize - it.size
                    elif realDiff < 0 and it.size + realDiff < it.minimumSize do
                        realDiff = it.minimumSize - it.size

                    it.size  += realDiff
                    dispatch -= realDiff
                }
            }
        }

        for item, [idx] in .items
        {
            let it = item!
            if !it.visible do
                continue

            .setPaneSizePrivate(cast(u32) idx, it.size)
        }
    }

    mtd hitTest(surfacePos: Math.Point)->u32
    {
        let client = .paddedClientRect()
        let local  = .surfaceToLocal(surfacePos)

        var x       = client.x
        var y       = client.y
        let barSize = .themeMetrics().splitView_BarSize

        var visibleIndex = 0
        for item, [idx] in .items
        {
            let it = item!
            if !it.visible do
                continue
            visibleIndex += 1
            if visibleIndex == .numVisiblePanes do
                break
            var rect = client
            if .isVertical()
            {
                rect.y      = y + it.size
                rect.height = barSize
                if rect.contains(local) do
                    return cast(u32) idx
                y = rect.bottom()
            }
            else
            {
                rect.x     = x + it.size
                rect.width = barSize
                if rect.contains(local) do
                    return cast(u32) idx
                x = rect.right()
            }
        }

        return Swag.U32.Max
    }

    mtd barRectAt(idx: u32)->Math.Rectangle
    {
        var result: retval = .paddedClientRect()

        let barSize = .themeMetrics().splitView_BarSize
        for item, [i] in .items
        {
            let pane = item!
            if !pane.visible do
                continue

            if .isVertical()
            {
                result.y      += pane.size
                result.height = barSize
            }
            else
            {
                result.x     += pane.size
                result.width = barSize
            }

            if i == idx do
                return result

            if .isVertical() do
                result.y += barSize
            else do
                result.x += barSize
        }

        Debug.assert(false, "splitter pane index is not visible")
        return result
    }

    mtd setPaneSizePrivate(idx: u32, newSize: f32)
    {
        let curPane = .items[idx]!
        Debug.assert(curPane.visible)

        var reqSize = Math.max(curPane.minimumSize, newSize)
        if curPane.maximumSize > 0 do
            reqSize = Math.min(curPane.maximumSize, reqSize)

        let requestedChange = reqSize - curPane.size
        if .numVisiblePanes == 1
        {
            curPane.size = reqSize
            return
        }

        var hasVisibleRight = false
        var scan            = cast(u64) idx + 1
        while scan < .items.count
        {
            if .items[scan]!.visible
            {
                hasVisibleRight = true
                break
            }

            scan += 1
        }

        let direction = hasVisibleRight ? 1 : -1
        var i         = cast(s32) idx
        var remaining = requestedChange

        for
        {
            i += direction
            if i < 0 or i >= .items.count do
                break

            let otherPane = .items[i]!
            if !otherPane.visible do
                continue

            var transfer = remaining
            if transfer > 0 do
                transfer = Math.min(transfer, Math.max(otherPane.size - otherPane.minimumSize, 0))
            elif transfer < 0 and otherPane.maximumSize > 0 do
                transfer = Math.max(transfer, otherPane.size - otherPane.maximumSize)

            otherPane.size -= transfer
            remaining      -= transfer
            if Math.abs(remaining) <= 0.001 do
                break
        }

        curPane.size += requestedChange - remaining
    }
}

impl SplitterCtrl
{
    // Creates an empty horizontal or vertical splitter.
    #[Swag.Discardable]
    func create(parent: *Wnd, position: Math.Rectangle = {}, vertical = false, id: #null WndId = null)->*SplitterCtrl
    {
        Debug.assert(parent != null)

        let pos = position
        let res = Wnd.create'SplitterCtrl(parent, null, pos, id)
        res.wndFlags |= .AfterChildrenPaint
        if vertical do
            res.flags.add(.Vertical)
        return res
    }

    // Reports whether panes are stacked vertically.
    #[Swag.Inline]
    mtd const isVertical() => .flags.has(.Vertical)

    // Adds `pane` and optionally creates a title label for it.
    #[Swag.Discardable]
    mtd addPane(pane: *Wnd, paneSize: f32 = 100, showTitle = false)->*SplitterItem
    {
        pane.setParent(me)
        .numVisiblePanes += 1

        let item = .items.allocate()
        item.view = pane
        if showTitle
        {
            with let label = Label.create(me, "")
            {
                .backgroundStyle = .Window
                .style.addStyleSheetColors("wnd_Bk $splitView_TitleBk")
            }

            item.label = label
        }

        .items.add(item)

        if .items.count == 1
        {
            let rect = .paddedClientRect()
            if .isVertical() do
                item.size = rect.height
            else do
                item.size = rect.width
        }
        else
        {
            .setPaneSize(cast(u32) .items.count - 1, paneSize)
        }

        return item
    }

    // Sets a pane size while respecting its limits and resizing adjacent visible panes.
    mtd setPaneSize(idx: u32, newSize: f32)
    {
        Debug.assert(idx < .items.count)
        .setPaneSizePrivate(idx, newSize)
        .sendResizeEvent()
    }

    // Shows or hides a pane and its optional title.
    mtd setPaneVisible(idx: u32, visible: bool)
    {
        Debug.assert(idx < .items.count)
        let pane = .items[idx]!

        if pane.visible == visible do
            return

        .numVisiblePanes += visible ? 1 : -1
        pane.visible     = visible
        if @isset(pane.view) do
            pane.view.show(visible)
        if pane.label do
            pane.label.show(visible)

        if visible
        {
            let mem = pane.size
            pane.size = 0
            .setPaneSize(idx, mem)
        }

        .sendResizeEvent()
    }

    // Reports whether a pane participates in layout.
    mtd const isPaneVisible(idx: u32)->bool
    {
        Debug.assert(idx < .items.count)
        return .items[idx]!.visible
    }
}
