#global public

using Core, Pixel

// Selects how rows can be selected in a list control.
enum ListSelectionMode
{
    None       // Disables row selection.
    Single     // Keeps at most one row selected.
    Multi      // Allows multiple selected rows.
}

// Configures list presentation and pointer behavior.
#[Swag.EnumFlags]
enum ListFlags
{
    None = 0                          // Uses the default list presentation and selection behavior.
    HideSelection                     // Hides selection while the list does not have focus.
    AlternateLines                    // Alternates row background colors.
    HorizontalLines                   // Draws horizontal row separators.
    VerticalLines                     // Draws vertical column separators.
    ReserveExpandMargin               // Reserves an expansion margin even when no row can expand.
    PreserveSelectionOnEmptyClick     // Keeps selection when empty space is clicked.
    HotTrack                          // Highlights the row under the pointer.
}

// Says where a drop hovering a list would land.
//
// A drop between two rows and a drop onto one row are different answers, and a list showing the
// gesture has to be able to draw both: an insertion is a rule in the gap, and a drop the row
// itself takes is the row outlined. See [[Gui.ListCtrl.dropMarkAt]].
enum ListDropMark
{
    None       // Nothing is being dragged over the list.
    Before     // The gap above the row, where an insertion would go.
    After      // The gap below the row.
    On         // The row itself, for a payload the row takes.
}

// Weight of the rule and of the outline a drop mark is drawn with, in logical units.
private const DropMarkThickness = 2.0'f32

// How far the cap at each end of an insertion rule reaches above and below it.
private const DropMarkCapReach = 3.0'f32

// Stores one cell in a [[Gui.ListLine]].
struct ListItem
{
    public
    {
        using item: Item                         // Embedded item state.
        sortKey:    String                       // Optional key used instead of the displayed label when sorting.
        colorBk:    Color                        // Cell background override, or transparent for the list color.
        colorFg:    Color                        // Cell foreground override, or transparent for the list color.
        column:     u32                          // Zero-based column index.
        horzAlign = StringHorzAlignment.Left     // Cell content alignment.
    }
}

// Stores one row and its optional child rows in a [[Gui.ListCtrl]].
struct ListLine
{
    public
    {
        colorBk:         Color           // Row background override, or transparent for the list color.
        colorFg:         Color           // Row foreground override, or transparent for the list color.
        userData0:       #null *void     // First application-defined pointer payload.
        userData1:       #null *void     // Second application-defined pointer payload.
        userData2:       #null *void     // Third application-defined pointer payload.
        userData3:       #null *void     // Fourth application-defined pointer payload.
        leftTextMargin:  f32             // Additional leading margin for this row.
        forceExpandMark: bool            // Whether to show an expansion mark without child rows.
        canCheck:        bool            // Whether the row exposes a check box.
        separator:       bool            // Whether the row is a non-selectable separator.
        iconMargin:      bool            // Whether to reserve icon space when the first cell has no icon.

        lines:    ArrayPtr'ListLine     // Direct child rows.
        items:    ArrayPtr'ListItem     // Cells indexed by their `column` field.
        parent:   #null *ListLine       // Parent row, or null for a root row.
        index:    u32                   // Stable row identity assigned by the owning list.
        level:    u32                   // Zero-based hierarchy depth.
        expanded: bool                  // Whether direct child rows are visible.
    }
}

// Displays selectable flat, multi-column, hierarchical, or virtual rows.
struct ListCtrl
{
    public
    {
        using frameWnd: FrameWnd     // Embedded frame wnd state.

        public readonly
        {
            horizontalExtent: f32                                // Explicit content width, or zero to derive it from the view or header.
            fixedLineHeight:  f32                                // Fixed row height, or zero to derive it from the font.
            indentWidth:      f32 = 22                           // Width added for each hierarchy level.
            iconSize:         f32                                // Square icon size, or zero to use each icon descriptor.
            iconMarginFirstCol    = true                         // Whether the first column reserves icon space.
            listFlags             = ListFlags.None               // Active presentation and pointer options.
            selectionMode         = ListSelectionMode.Single     // Active row-selection policy.
            leftTextMargin:   f32                                // Leading text margin shared by all rows.
            virtualCount:     u32                                // Number of rows supplied by `onFillVirtualLine`.
            isVirtual:        bool                               // Whether row data is supplied on demand.

            #[Swag.Late]
            {
                scrollWnd: *ScrollWnd     // Scrolling container.
                listView:  *ListView      // Row-rendering and input view.
                header:    *Header        // Column header, available for multi-column lists.
            }
        }

        sigSelectionChanged:  SigArray'func||(*ListCtrl)                                       // Emitted after the selected row set changes.
        sigCheckedChanged:    SigArray'func||(*ListCtrl)                                       // Emitted after the checked row set changes.
        sigRightClicked:      SigArray'func||(*ListCtrl, Math.Point)                           // Emitted for a right click, with the local position.
        sigLeftDoubleClicked: SigArray'func||(*ListCtrl, Math.Point)                           // Emitted for a left double click, with the local position.
        sigExpanded:          SigArray'func||(*ListCtrl, *ListLine)                            // Emitted after a row expands.
        sigCollapsed:         SigArray'func||(*ListCtrl, *ListLine)                            // Emitted after a row collapses.
        sigKeyPressed:        SigArray'func||(*ListCtrl, *KeyEvent)                            // Emitted for a key press before the list reads it; accept the event to claim the key.
        onFillVirtualLine:    #null func(*ListCtrl, #null *ListLine, u32)                      // Fills a transient row before a virtual row is painted.
        compareLines:         #null func(#null *ListLine, #null *ListLine, u32, bool)->s32     // Compares two rows for custom sorting.

        internal
        {
            toFreeLines:      ArrayPtr'ListLine           // Owns every allocated root row.
            lines:            Array'(#null *ListLine)     // Visible rows in display order.
            idxLineToIdxList: HashTable'(u32, u32)        // Maps stable row identities to visible indexes.
            selModel:         SelModel                    // Selected stable row identities.
            checkModel:       SelModel                    // Checked stable row identities.
            nextLineIndex:    u32                         // Identity assigned to the next created row.
        }

        // Where the keyboard and the mouse currently are in the list. The list moves them as it
        // handles events; move the focus with 'setFocusIndex'.
        public readonly
        {
            focusIndex = Swag.U32.Max     // Row the keyboard focus is on.
            hotIndex   = Swag.U32.Max     // Row under the mouse.
        }

        // Where a drop hovering the list would land. The list never sets these itself: a window
        // showing a drag decides what it accepts, and says so with 'setDropMark'.
        public readonly
        {
            dropMarkIndex = Swag.U32.Max          // Row the mark is drawn against.
            dropMark      = ListDropMark.None     // What the mark says about that row.
        }
    }
}

// Hosts the scrollable, painted row viewport of a [[Gui.ListCtrl]].
struct ListView
{
    public
    {
        using wnd: Wnd     // Embedded wnd state.
        #[Swag.Late]
        list: *ListCtrl     // List associated with this value.

        // Set when a press was consumed by something else, so the matching release is ignored.
        internal
        {
            discardMouseRelease: bool
            selectionRailY:      f32      // Animated top edge of the single-selection rail.
            hasSelectionRail:    bool     // Whether a selected row has initialized the rail.
        }
    }
}

impl ListLine
{
    // Returns whether parent of.
    mtd isParentOf(other: *ListLine)->bool
    {
        var l = other.parent
        while l and l != me do
            l = l.parent
        return l ? true : false
    }

    // Returns whether this value can expand.
    #[Swag.Inline]
    mtd canExpand()->bool
    {
        return .forceExpandMark or !.lines.isEmpty()
    }

    // Returns the cell assigned to `column`.
    mtd itemAt(column: u32)->*ListItem
    {
        Debug.assert(column < .items.count)
        for itemIt in .items
        {
            let item = itemIt!
            if item.column == column do
                return item
        }

        unreachable
    }

    // Initialize a given column item
    // Creates simple.
    // Creates multi columns.
    #[Swag.Discardable]
    mtd setItem(column: u32, name: string, icon: Icon = {})->*ListItem
    {
        for itemIt in .items
        {
            let item = itemIt!
            if item.column == column
            {
                item.name = name
                item.icon = icon
                return item
            }
        }

        let item = .items.allocate()
        item.column = column
        item.name   = name
        item.icon   = icon
        .items.add(item)
        return item
    }
}

impl IWnd for ListView
{
    mtd impl onResizeEvent(evt: *ResizeEvent)
    {
        if @isset(.list) do
            .list.computeLayout()
    }

    // Reads the keys that move through the lines, and declines every other one.
    //
    // What the list does not use belongs to the surface: Escape backs out of the box the list sits
    // in and Tab leaves the list. Marking every key handled — which an empty list did too — made a
    // file box unanswerable from the keyboard, since that is the control it opens the keyboard on.
    //
    // [[Gui.ListCtrl.sigKeyPressed]] is offered the key first and claims it by accepting the
    // event, so a browsing gesture answering Enter is not also read here as a row folding.
    mtd impl onKeyEvent(evt: *KeyEvent)
    {
        evt.accepted = false
        if evt.kind != .Pressed do
            return

        .list.sigKeyPressed.call(.list, evt)
        if evt.accepted do
            return

        let lineCount = .list.lineCount()
        if !lineCount do
            return

        var focusLine: #null *ListLine
        if .list.focusIndex < .list.lines.count do
            focusLine = .list.lines[.list.focusIndex]

        var shift = cast(bool) (evt.modifiers & .Shift)
        let ctrl  = cast(bool) (evt.modifiers & .Control)

        if .list.focusIndex == Swag.U32.Max
        {
            if evt.key != .Down do
                return
        }

        var selChanged = false
        var startSelIdx, endSelIdx: u32

        switch evt.key
        {
        case .Space where focusLine:
            evt.accepted = true
            if focusLine!.canCheck
            {
                for l in .list.selModel
                {
                    let res = .list.idxLineToIdxList.tryFind(l)
                    if !res do
                        continue
                    let idx = res.value
                    if !.list.lines[idx]!.canCheck do
                        continue
                    let checked = !.list.checkModel.isSelected(l)
                    .list.checkModel.setSelected(l, checked)
                }

                .list.sigCheckedChanged.call(.list)
                .invalidate()
            }
            else
            {
                .list.toggleExpand(focusLine!)
            }

        case .Enter where focusLine:
            evt.accepted = true
            if focusLine!.canCheck
            {
                for l in .list.selModel
                {
                    let res = .list.idxLineToIdxList.tryFind(l)
                    if !res do
                        continue
                    let idx = res.value
                    if !.list.lines[idx]!.canCheck do
                        continue
                    .list.checkModel.select(l)
                }

                .list.sigCheckedChanged.call(.list)
                .invalidate()
            }
            else
            {
                .list.toggleExpand(focusLine!)
            }

        case .A:
            if !ctrl or .list.selectionMode == .Single do
                break
            shift = true
            .list.selModel.clear()
            endSelIdx   = 0
            startSelIdx = .list.lineCount() - 1
            selChanged  = true

        case .Home:
            startSelIdx = .list.focusIndex
            endSelIdx   = 0
            selChanged  = true

        case .End:
            startSelIdx = .list.focusIndex
            endSelIdx   = lineCount - 1
            selChanged  = true

        case .Up:
            if .list.focusIndex == 0 do
                startSelIdx, endSelIdx = 0
            else do
                startSelIdx, endSelIdx = .list.focusIndex - 1
            selChanged = true

        case .Down:
            if .list.focusIndex == lineCount - 1 do
                startSelIdx, endSelIdx = lineCount - 1
            elif .list.focusIndex == Swag.U32.Max do
                .list.focusIndex = 0
            else do
                startSelIdx, endSelIdx = .list.focusIndex + 1
            selChanged = true

        case .Left where focusLine:
            evt.accepted = true
            .list.collapse(focusLine!)

        case .Right where focusLine:
            evt.accepted = true
            .list.expand(focusLine!)

        case .PageDown:
            let first = .list.firstVisibleLineIndex()
            let last  = .list.lastVisibleLineIndex()
            startSelIdx, endSelIdx = .list.focusIndex + (last - first)
            startSelIdx            = Math.min(startSelIdx, lineCount - 1)
            endSelIdx              = Math.min(endSelIdx, lineCount - 1)
            selChanged             = true

        case .PageUp:
            let first  = .list.firstVisibleLineIndex()
            let last   = .list.lastVisibleLineIndex()
            let offset = last - first
            if offset > .list.focusIndex do
                startSelIdx, endSelIdx = 0
            else do
                startSelIdx, endSelIdx = .list.focusIndex - offset
            selChanged = true
        }

        if selChanged
        {
            evt.accepted = true
            if !shift or .list.selectionMode == .Single
            {
                .list.selModel.clear()
                startSelIdx = endSelIdx
            }

            .list.selectLines(startSelIdx, endSelIdx)
            .list.focusIndex = endSelIdx
            .list.ensureVisibleLine(.list.focusIndex)
        }
    }

    mtd impl onMouseEvent(evt: *MouseEvent)
    {
        if evt.kind == .Leave
        {
            .list.hotIndex = Swag.U32.Max
            .invalidate()
            evt.accepted = false
            return
        }

        let idx = .hitTest(evt.surfacePos)
        if idx != .list.hotIndex and .list.listFlags.has(.HotTrack)
        {
            .list.hotIndex = idx
            .invalidate()
        }

        if evt.kind != .Pressed and evt.kind != .Released and evt.kind != .DoubleClick
        {
            evt.accepted = false
            return
        }

        let metrics = .themeMetrics()

        let ctrl  = cast(bool) (evt.modifiers & .Control)
        let shift = cast(bool) (evt.modifiers & .Shift)

        // Right mouse button
        // ============================

        if evt.button == .Right
        {
            if idx != Swag.U32.Max and !shift and !ctrl
            {
                if evt.kind == .Pressed
                {
                    let idxLine = .list.isVirtual ? idx : .list.lines[idx]!.index
                    if !.list.selModel.isSelected(idxLine)
                    {
                        .list.selModel.clear()
                        .list.selModel.select(idxLine)
                        .list.focusIndex = idx
                        .invalidate()
                    }
                }
                elif evt.kind == .Released
                {
                    let pt = .surfaceToLocal(evt.surfacePos)
                    .list.sigRightClicked.call(.list, pt)
                }
            }

            return
        }

        if evt.button != .Left do
            return

        if idx != Swag.U32.Max and !.list.isVirtual
        {
            let hitLine  = .list.lines[idx]!
            let idxLine  = hitLine.index
            var localPos = .surfaceToLocal(evt.surfacePos)
            localPos.x += .scrollPos.x
            var widthLeft = hitLine.level * .list.indentWidth
            if localPos.x >= widthLeft
            {
                // Expand
                // ============================

                widthLeft += Math.min(metrics.btnCheck_Size, .list.lineHeight())
                if hitLine.canExpand()
                {
                    var eatCheck = false
                    if localPos.x < widthLeft do
                        eatCheck = true
                    widthLeft += Math.min(metrics.btnCheck_Size, .list.lineHeight())

                    if eatCheck
                    {
                        if evt.kind == .Released do
                            return
                        .list.toggleExpand(.list.lines[idx]!)
                        return
                    }
                }

                // Check boxes
                // ============================

                // On checkbox
                if hitLine.canCheck
                {
                    var eatCheck = false
                    if evt.kind == .DoubleClick do
                        eatCheck = true
                    elif localPos.x < widthLeft do
                        eatCheck = true

                    if eatCheck
                    {
                        if evt.kind == .Released do
                            return

                        let checked = !.list.checkModel.isSelected(idxLine)
                        if .list.selModel.isSelected(idxLine)
                        {
                            for l in .list.selModel do
                                .list.checkModel.setSelected(l, checked)
                        }
                        else do
                            .list.checkModel.setSelected(idxLine, checked)
                        .list.sigCheckedChanged.call(.list)
                        .invalidate()
                        return
                    }
                }
            }
        }

        // User double click
        // ============================

        if evt.kind == .DoubleClick
        {
            if idx != Swag.U32.Max and !.list.isVirtual do
                .list.toggleExpand(.list.lines[idx]!)
            let pt = .surfaceToLocal(evt.surfacePos)
            .list.sigLeftDoubleClicked.call(.list, pt)
            return
        }

        // Selection by left button
        // ============================

        if .list.selectionMode == .None do
            return

        // We select by mouse release when the hittest line is selected
        if evt.kind == .Pressed and idx != Swag.U32.Max and .list.isLineSelected(idx)
        {
            .discardMouseRelease = false
            return
        }

        if evt.kind == .Released and .discardMouseRelease
        {
            return
        }

        .discardMouseRelease = evt.kind == .Pressed

        let canUnsel = idx != Swag.U32.Max or !.list.listFlags.has(.PreserveSelectionOnEmptyClick)
        if canUnsel and (.list.selectionMode == .Single or (!ctrl and !shift)) do
            .list.selModel.clear()

        if idx != Swag.U32.Max
        {
            // Range selection
            if shift and .list.selectionMode == .Multi
            {
                let startIdx = .list.focusIndex == Swag.U32.Max ? 0 : .list.focusIndex
                let idx0     = Math.min(startIdx, idx)
                let idx1     = Math.max(startIdx, idx)
                for i in idx0 to idx1
                {
                    let idxLine = .list.isVirtual ? i : .list.lines[i]!.index
                    .list.selModel.select(idxLine)
                }
            }

            // Invert selection
            else
            {
                let idxLine = .list.isVirtual ? idx : .list.lines[idx]!.index
                let toSel   = !.list.selModel.isSelected(idxLine)
                .list.selModel.setSelected(idxLine, toSel)
            }
        }

        if canUnsel do
            .list.focusIndex = idx
        .invalidate()
        if canUnsel or idx != Swag.U32.Max do
            .list.sigSelectionChanged.call(.list)
    }

    mtd impl onPaint(evt: *PaintEvent)
    {
        if .list.lineCount() != 0 do
            .paintRows(evt.paintContext)
        .paintDropMark(evt.paintContext)
    }

    mtd paintRows(bc: PaintContext)
    {
        let painter = bc.painter
        let colors  = .themeColors()
        let metrics = .themeMetrics()

        var rect: Math.Rectangle
        rect.width  = .displayWidth()
        rect.height = .list.lineHeight()

        // Clipping, take care of padding
        var clipRect = .surfaceRect()
        clipRect.applyPadding(.padding)

        let firstIdx           = .list.firstVisibleLineIndex()
        let lastIdx            = .list.lastVisibleLineIndex()
        let reserveCheckMargin = !.list.isVirtual and .list.hasVisibleCheckBoxes()

        if .list.selectionMode == .Single and
           !.app().animator.isActive(me, AnimationChannel.from("Gui.List.SelectionRail"))
        {
            let selected = .selectedVisibleIndex()
            .hasSelectionRail = selected != Swag.U32.Max
            if .hasSelectionRail do
                .selectionRailY = cast(f32) selected * .list.lineHeight()
        }

        // Do not display with bigs coordinates to avoid precision issues
        // So we: the scroll by hand, and draw will small coordinates
        var y = cast(f64) firstIdx * .list.lineHeight()
        y      -= .scrollPos.y
        rect.y = cast(f32) y

        if .list.isVirtual
        {
            let fillVirtualLine = .list.onFillVirtualLine!
            for i in firstIdx to lastIdx
            {
                var line: ListLine
                fillVirtualLine(.list!, &line, i)
                .paintLine(bc, i, &line, rect, line.canCheck)
                rect.y = rect.bottom()

                if .list.listFlags.has(.HorizontalLines) do
                    painter.drawLine(rect.x, rect.y, rect.right(), rect.y, colors.listItem_Line, 1)
            }
        }
        else
        {
            for i in firstIdx to lastIdx
            {
                let line = .list.lines[i]
                .paintLine(bc, i, line!, rect, reserveCheckMargin)
                rect.y = rect.bottom()

                if .list.listFlags.has(.HorizontalLines) do
                    painter.drawLine(rect.x, rect.y, rect.right(), rect.y, colors.listItem_Line, 1)
            }
        }

        if .list.selectionMode == .Single and .hasSelectionRail and colors.activeRail.a
        {
            let rail = Math.Rectangle{rect.x, .selectionRailY - .scrollPos.y, metrics.activeRail_Size, .list.lineHeight()}
            painter.fillRect(rail, colors.activeRail)
        }

        if @isset(.list.header) and .list.listFlags.has(.VerticalLines)
        {
            rect = .paddedClientRect()
            for idx in 1 until .list.header.items.count
            {
                var x = .columnPosition(.list.header.items[idx]!.column)
                x -= .scrollPos.x
                x -= metrics.header_Separator * 0.5
                painter.drawLine(x, rect.y, x, rect.bottom(), colors.listItem_Line, 1)
            }

            let last = .list.header.items.back()!
            var x    = .columnPosition(last.column)
            x -= .scrollPos.x
            x += last.width
            x += metrics.header_Separator * 0.5
            painter.drawLine(x, rect.y, x, rect.bottom(), colors.listItem_Line, 1)
        }
    }
}

private impl ListView
{
    // Draws where a drop hovering the list would land.
    //
    // An insertion is a rule in the gap with a cap at each end, the way a file manager draws one,
    // and a drop the row itself takes is that row outlined. Both are the accent, because the mark
    // has to read over a selected row and over an alternating ground alike.
    mtd paintDropMark(bc: PaintContext)
    {
        if .list.dropMark == .None do
            return

        let painter = bc.painter
        let color   = .themeColors().hilight
        let height  = .list.lineHeight()
        let width   = .displayWidth()

        var y = cast(f64) .list.dropMarkIndex * height
        y -= .scrollPos.y
        if .list.dropMark == .After do
            y += height

        // An empty list has no row to sit against, so the mark goes to the top of the viewport.
        if .list.lineCount() == 0 do
            y = 0

        if .list.dropMark == .On
        {
            painter.drawRect(0, cast(f32) y, width, height, color, DropMarkThickness)
            return
        }

        // The rule is centred on the gap rather than drawn below it, so the same edge reads the
        // same whether it was reached from the row above or the row below.
        let line = cast(f32) y - DropMarkThickness * 0.5
        painter.drawLine(0, line, width, line, color, DropMarkThickness)
        painter.fillRect(0, line - DropMarkCapReach, DropMarkThickness, DropMarkCapReach * 2 + DropMarkThickness, color)
        painter.fillRect(width - DropMarkThickness, line - DropMarkCapReach, DropMarkThickness, DropMarkCapReach * 2 + DropMarkThickness, color)
    }

    mtd selectedVisibleIndex()->u32
    {
        if .list.selModel.isEmpty() do
            return Swag.U32.Max

        let selected = .list.selModel.ranges()[0].start
        if .list.isVirtual do
            return selected < .list.virtualCount ? selected : Swag.U32.Max

        let found = .list.idxLineToIdxList.tryFind(selected)
        return found ? found.value : Swag.U32.Max
    }

    mtd animateSelectionRail()
    {
        let channel = AnimationChannel.from("Gui.List.SelectionRail")
        if .list.selectionMode != .Single
        {
            .app().animator.cancel(me, channel)
            .hasSelectionRail = false
            return
        }

        let index = .selectedVisibleIndex()
        if index == Swag.U32.Max
        {
            .app().animator.cancel(me, channel)
            .hasSelectionRail = false
            .invalidate()
            return
        }

        let destination = cast(f32) index * .list.lineHeight()
        if !.hasSelectionRail
        {
            .selectionRailY   = destination
            .hasSelectionRail = true
            .invalidate()
            return
        }

        var options: AnimationOptions
        options.duration = Time.Duration.fromSeconds(.themeMetrics().motion_QuickSeconds)
        options.easing   = .EaseOut
        discard .app().animator.animateF32(me,
                                           channel,
                                           .selectionRailY,
                                           destination,
                                           func|view=me|(animationWnd, value)
                                           {
                                               discard animationWnd
                                               view.selectionRailY = value
                                           },
                                           options)
    }

    mtd columnPosition(column: u32)->f32
    {
        var x = .list.header.itemPositionForColumn(column)
        x += .list.header.surfaceRect().x
        x -= .surfaceRect().x
        return x
    }

    mtd paintLine(bc: PaintContext, idx: u32, line: *ListLine, rect: Math.Rectangle, reserveCheckMargin: bool)
    {
        let painter = bc.painter
        let theme   = .theme()
        let colors  = .themeColors()
        let metrics = .themeMetrics()
        let rects   = .themeRects()

        // Selection box
        let isSelected  = .list.isLineSelected(idx)
        let canHotTrack = .list.isVirtual or !line.separator
        let hideSel     = .list.listFlags.has(.HideSelection)
        if isSelected and (!hideSel or .hasFocus()) and !bc.isDisabled
        {
            let colorSel = .hasFocus() ? colors.listItem_FocusSelectedBk : colors.listItem_SelectedBk
            painter.fillRect(rect, colorSel)
            if colors.activeRail.a and .list.selectionMode != .Single
            {
                let rail = Math.Rectangle{rect.x, rect.y, metrics.activeRail_Size, rect.height}
                painter.fillRect(rail, colors.activeRail)
            }
        }

        // Hot box
        elif idx == .list.hotIndex and .list.listFlags.has(.HotTrack) and canHotTrack
        {
            painter.fillRect(rect, colors.listItem_HotBk)
        }

        // User background
        elif line.colorBk.a
        {
            painter.fillRect(rect, line.colorBk)
        }

        // Alternate lines
        elif .list.listFlags.has(.AlternateLines) and idx % 2 == 1
        {
            painter.fillRect(rect, colors.listItem_AlternateBk)
        }

        var colorText, colorExpand: Color = undefined
        switch
        {
        case bc.isDisabled:
            colorText, colorExpand = colors.listItem_DisabledText

        case isSelected:
            colorText, colorExpand = .hasFocus() ? colors.listItem_FocusSelectedText : colors.listItem_SelectedText

        case line.colorFg.a:
            colorText   = line.colorFg
            colorExpand = colors.listItem_Text

        default:
            if line.separator do
                colorText, colorExpand = colors.listItem_Separator
            else do
                colorText, colorExpand = colors.listItem_Text
        }

        var format: RichStringFormat
        for itemIt, idxItem in line.items
        {
            let item           = itemIt!
            var colorFg: Color = undefined
            if item.colorFg.a and !isSelected do
                colorFg = item.colorFg
            else do
                colorFg = colorText
            theme.setTextColors(&format, colorFg)
            format.horzAlignment = item.horzAlign
            format.vertAlignment = .Center
            format.flags         = .Clip
            format.font          = .list.font()

            var labelPos = rect

            // Right
            if @isset(.list.header)
            {
                labelPos.x     = .columnPosition(item.column)
                labelPos.width = .list.header.itemWidthForColumn(item.column)
            }

            labelPos.x -= .scrollPos.x
            labelPos.x += .list.leftTextMargin + line.leftTextMargin

            // A row keeps its content clear of its own leading edge. Pressed against it, the
            // glyph sits on the selection band with nothing between them — and, in a theme that
            // rails, directly against the rule marking the current row, which then reads as an
            // outline drawn around the glyph rather than as a mark beside it. A list with a
            // header takes that air from the header's own column inset instead; adding it here
            // as well would slide every cell out from under its title.
            if !@isset(.list.header)
            {
                let gutter = metrics.activeRail_Size + metrics.activeRail_Margin
                labelPos.moveLeft(gutter)
            }

            if idxItem == 0
            {
                // Ident level
                labelPos.moveLeft(line.level * .list.indentWidth)

                // Expand/collapse mark
                let canExpand = line.canExpand()
                if canExpand or .list.listFlags.has(.ReserveExpandMargin)
                {
                    if canExpand
                    {
                        // Centered in the column the row reserves for it, so the marker keeps the
                        // same air on both sides whatever size the theme gives the chevron.
                        let expand  = theme.icon(line.expanded ? .ChevronDown : .ChevronRight, metrics.chevron_Size)
                        let expandX = labelPos.x + Math.max(metrics.list_ExpandSize - expand.sizeX, 0.0) * 0.5
                        expand.paint(painter, expandX, opticalTop(.font(), labelPos.vertCenter(), expand.sizeY), colorExpand)
                    }

                    labelPos.moveLeft(metrics.list_ExpandSize)
                }
            }

            // Background color ?
            if item.colorBk.a and !isSelected
            {
                var rectPos = labelPos
                rectPos.width += metrics.header_Separator * 0.5
                painter.fillRect(rectPos, item.colorBk)
            }

            painter.pushClippingRect(labelPos)
            defer painter.popClippingRect()

            // Checkbox
            if idxItem == 0 and reserveCheckMargin
            {
                let widthCheck = Math.min(metrics.btnCheck_Size, .list.lineHeight())
                if line.canCheck
                {
                    var subRectBorder: *ThemeImageRect = &rects.btnCheck_NormalBorder

                    let idxLine = .list.isVirtual ? idx : line.index
                    let checked = .list.checkModel.isSelected(idxLine)

                    let colorBorder = colorFg
                    let colorMark   = colorFg

                    if checked
                    {
                        subRectBorder = &rects.btnCheck_CheckedBorder
                    }

                    var posBox = labelPos
                    posBox.height = widthCheck
                    posBox.y      = opticalTop(.font(), labelPos.vertCenter(), posBox.height)
                    posBox.width  = posBox.height
                    if checked do
                        theme.drawSubRect(painter, posBox, &rects.btnCheck_CheckedMark, colorMark)
                    theme.drawSubRect(painter, posBox, subRectBorder, colorBorder)
                }

                labelPos.moveLeft(widthCheck + 4)
            }

            // Take care of header item margin
            if @isset(.list.header) do
                labelPos.moveLeft(.list.header.itemPadding)

            // Left margin, or icon
            var icon = item.icon
            if .list.iconSize > 0
            {
                if icon.isValid() do
                    icon.sizeX, icon.sizeY = .list.iconSize
                else
                {
                    var iconMargin = .list.iconMarginFirstCol
                    if !idxItem and line.parent do
                        iconMargin = line.parent.iconMargin
                    elif idxItem do
                        iconMargin = .list.header.itemAt(cast(u32) idxItem).reservesIconSpace
                    if iconMargin do
                        labelPos.moveLeft(.list.iconSize + metrics.iconText_Margin)
                }
            }

            Theme.drawIconText(painter, labelPos, icon, &item.name, format, metrics.iconText_Margin)
        }
    }

    mtd hitTest(surfacePos: Math.Point)->u32
    {
        let lc  = .list.lineCount()
        var res = .surfaceToLocal(surfacePos)
        if res.x < 0 or res.y < 0 do
            return Swag.U32.Max
        res.y += .scrollPos.y
        let idx = cast(u32) (res.y / .list.lineHeight())
        if idx >= lc do
            return Swag.U32.Max
        if !.list.isVirtual and .list.lines[idx]!.separator do
            return Swag.U32.Max
        return idx
    }

    mtd displayWidth()->f32
    {
        if .list.horizontalExtent > 0 do
            return .list.horizontalExtent
        return .position.width
    }
}

impl ListCtrl
{
    // Changes the row-selection policy and normalizes the current selection.
    mtd setSelectionMode(mode: ListSelectionMode)
    {
        if .selectionMode == mode do
            return
        .selectionMode = mode
        if mode == .None
        {
            .unselectAll()
            return
        }

        if mode == .Single and .selModel.selectedCount() > 1
        {
            let first = .selModel.ranges()[0].start
            .selModel.clear()
            .selModel.select(first)
            .invalidate()
            .sigSelectionChanged.call(me)
        }
    }

    // Says where a drop released at `surfacePos` would land.
    //
    // The outer quarter of a row reads as the gap next to it and the middle half reads as the row
    // itself, which is the convention a file manager trains every reader on. A position past the
    // last row answers the gap after it, so a list is appended to by aiming at its empty part, and
    // an empty list answers `Before` on row zero.
    //
    // This is only the geometry. What a drop means is the window's decision, so a list that
    // inserts and a list that drops onto a row both call this and then keep the answer they want.
    mtd dropMarkAt(surfacePos: Math.Point)->{ index: u32, mark: ListDropMark }
    {
        var result: retval

        var local = .listView.surfaceToLocal(surfacePos)
        if local.x < 0 or local.y < 0
        {
            result.index = Swag.U32.Max
            return result
        }

        // An empty list is a place a first row can be dropped into, so it answers the gap before
        // the row that is not there rather than refusing the gesture.
        let count = .lineCount()
        if !count
        {
            result.mark = .Before
            return result
        }

        local.y += .listView.scrollPos.y

        let height = .lineHeight()
        let row    = cast(u32) (local.y / height)
        if row >= count
        {
            result.index = count - 1
            result.mark  = .After
            return result
        }

        result.index = row

        let inside = local.y - cast(f32) row * height
        if inside < height * 0.25 do
            result.mark = .Before
        elif inside > height * 0.75 do
            result.mark = .After
        else do
            result.mark = .On

        return result
    }

    // Shows where a drop would land, repainting only when the answer changed.
    //
    // A window showing a drag calls this from its `Over` phase with whatever
    // [[Gui.ListCtrl.dropMarkAt]] answered, or with a mark of its own when it only ever inserts.
    mtd setDropMark(index: u32, mark: ListDropMark)
    {
        let shown = mark != .None ? index : Swag.U32.Max
        if .dropMarkIndex == shown and .dropMark == mark do
            return

        .dropMarkIndex = shown
        .dropMark      = mark
        .listView.invalidate()
    }

    // Stops showing where a drop would land, which every `Leave` and `Drop` phase has to do.
    mtd clearDropMark()
    {
        .setDropMark(Swag.U32.Max, .None)
    }

    // Adds and removes presentation or pointer options, then repaints the list.
    mtd updateFlags(add: ListFlags = .None, remove = ListFlags.None)
    {
        var flags = .listFlags
        flags.add(add)
        flags.remove(remove)
        if flags == .listFlags do
            return
        .listFlags = flags
        .invalidate()
    }

    // Sets an explicit content width; zero derives it from the view or header.
    mtd setHorizontalExtent(width: f32)
    {
        Debug.assert(width >= 0, "horizontal extent cannot be negative")
        if .horizontalExtent == width do
            return
        .horizontalExtent = width
        .computeLayout()
    }

    // Sets a fixed row height; zero derives it from the current font.
    mtd setLineHeight(height: f32)
    {
        Debug.assert(height >= 0, "line height cannot be negative")
        if .fixedLineHeight == height do
            return
        .fixedLineHeight = height
        .computeLayout()
    }

    // Changes the indentation applied at each hierarchy level.
    mtd setIndentWidth(width: f32)
    {
        Debug.assert(width >= 0, "indent width cannot be negative")
        if .indentWidth == width do
            return
        .indentWidth = width
        .invalidate()
    }

    // Changes the square icon draw size; zero preserves icon descriptor sizes.
    mtd setIconSize(size: f32)
    {
        Debug.assert(size >= 0, "icon size cannot be negative")
        if .iconSize == size do
            return
        .iconSize = size
        .invalidate()
    }

    // Controls whether the first column reserves icon space for rows without icons.
    mtd setFirstColumnIconMargin(enabled: bool)
    {
        if .iconMarginFirstCol == enabled do
            return
        .iconMarginFirstCol = enabled
        .invalidate()
    }

    // Changes the leading text margin shared by all rows.
    mtd setLeftTextMargin(margin: f32)
    {
        Debug.assert(margin >= 0, "left text margin cannot be negative")
        if .leftTextMargin == margin do
            return
        .leftTextMargin = margin
        .invalidate()
    }

    // Creates a list without a column header.
    #[Swag.Discardable]
    func createSimple(parent: *Wnd, position: Math.Rectangle = {}, id: #null WndId = null)->*ListCtrl
    {
        Debug.assert(parent != null)
        with let list = Wnd.create'ListCtrl(parent, "", position, id)
        {
            // The list is one stop of the keyboard traversal, and the view inside it is what
            // reads the keys: the rows, the selection and the scrolling all live there.
            .focusPolicy         = .Tab
            .wndFlags            |= .NoFocusRing
            .scrollWnd           = .createView'ScrollWnd()
            .scrollWnd.dockStyle = .Center
            .scrollWnd.setAllPaddings(.themeMetrics().list_Padding)

            .listView             = .scrollWnd.createView'ListView()
            .listView.list        = list
            .listView.focusPolicy = .Inner
            .listView.wndFlags    |= .NoScroll
            .focusDelegate        = .listView
            .sigSelectionChanged  += func|view=.listView|(changedList)
            {
                discard changedList
                view.animateSelectionRail()
            }
        }

        return list
    }

    // Creates a list control configured for multiple columns.
    #[Swag.Discardable]
    func createMultiColumns(parent: *Wnd, position: Math.Rectangle = {}, id: #null WndId = null)->*ListCtrl
    {
        Debug.assert(parent != null)
        let list = Wnd.create'ListCtrl(parent, "", position, id)

        let fwnd = list.createView'Wnd()
        fwnd.dockStyle = .Center
        fwnd.wndFlags  ^= .ClipChildren

        // Adapt header to the frame container
        list.hookOnEvent = func(wnd, evt)
        {
            if !evt is ResizeEvent do
                return false

            var list = cast(*ListCtrl) wnd
            if !@isset(list.header) do
                return false
            var header = list.header
            if header.form == .Transparent do
                return false
            switch list.frameForm
            {
            case .Round:
                header.form   = .Round
                header.margin = -wnd.themeMetrics().frameWnd_RoundPadding

            case .Square:
                header.form   = .Flat
                header.margin = -wnd.themeMetrics().frameWnd_SquarePadding

            case .Transparent:
                header.form   = .Flat
                header.margin = -wnd.themeMetrics().frameWnd_FlatPadding
            }

            header.setMargin(bottom: 0)
            return false
        }

        with list
        {
            // One stop for the whole control, on the view that reads the keys.
            .focusPolicy = .Tab
            .wndFlags    |= .NoFocusRing

            // Header
            // Need to recompute layout when header size has changed
            .header                  = Header.create(fwnd, {})
            .header.dockStyle        = .Top
            .header.form             = .Round
            .header.sigLayoutChanged += func|list|(header) { list.computeLayout() }

            .header.sigColumnClicked += func|list|(header, column)
            {
                let descending = header.sortColumn == column and header.sortDirection == .Ascending
                list.sort(column, descending, persistent: true)
            }

            // Scroll that contains the list view
            .scrollWnd                 = Wnd.create'ScrollWnd(fwnd, {})
            .scrollWnd.dockStyle       = .Center
            .scrollWnd.backgroundStyle = .Transparent
            .scrollWnd.setAllPaddings(.themeMetrics().list_Padding)
            .scrollWnd.sigScrollPositionChanged += func|header = list.header|(scrollWnd, op, np)
            {
                header.scrollPos.x = np.x
                header.invalidate()
            }

            // ListCtrl view
            .listView             = .scrollWnd.createView'ListView()
            .listView.list        = list
            .listView.focusPolicy = .Inner
            .listView.wndFlags    |= .NoScroll
            .focusDelegate        = .listView
            .sigSelectionChanged  += func|view=.listView|(changedList)
            {
                discard changedList
                view.animateSelectionRail()
            }
        }

        return list
    }

    // Clears the selected row set and emits [[Gui.ListCtrl.sigSelectionChanged]] when needed.
    mtd unselectAll()
    {
        if .selModel.isEmpty() do
            return
        .selModel.clear()
        .invalidate()
        .sigSelectionChanged.call(me)
    }

    // Reports whether the row at `index` is selected.
    mtd const isLineSelected(idx: u32)->bool
    {
        Debug.assert(idx < .lineCount())
        if .selectionMode == .None do
            return false
        if .isVirtual do
            return .selModel.isSelected(idx)
        let line = .lines[idx]!
        return !line.separator and .selModel.isSelected(line.index)
    }

    // Selects or unselects one row and emits [[Gui.ListCtrl.sigSelectionChanged]] when needed.
    mtd selectLine(idx: u32, select: bool = true)
    {
        let lineCount = .lineCount()
        Debug.assert(idx < lineCount)

        if .selectionMode == .None or lineCount == 0 do
            return
        if !.isVirtual and .lines[idx]!.separator do
            return

        let idxLine     = .isVirtual ? idx : .lines[idx]!.index
        let wasSelected = .selModel.isSelected(idxLine)
        if .selectionMode == .Single and select
        {
            if wasSelected and .selModel.selectedCount() == 1 do
                return
            .selModel.clear()
            .selModel.select(idxLine)
        }
        else
        {
            if wasSelected == select do
                return
            .selModel.setSelected(idxLine, select)
        }

        .invalidate()
        .sigSelectionChanged.call(me)
    }

    // Selects or unselects an inclusive row range.
    mtd selectLines(start, end: u32, select: bool = true)
    {
        let lineCount = .lineCount()
        Debug.assert(start < lineCount)
        Debug.assert(end < lineCount)

        if .selectionMode == .None or lineCount == 0 do
            return

        if .selectionMode == .Single and select
        {
            .selectLine(end)
            return
        }

        let idx0    = Math.min(start, end)
        let idx1    = Math.max(start, end)
        var changed = false
        for i in idx0 to idx1
        {
            if !.isVirtual and .lines[i]!.separator do
                continue
            let idxLine = .isVirtual ? i : .lines[i]!.index
            if .selModel.isSelected(idxLine) == select do
                continue
            .selModel.setSelected(idxLine, select)
            changed = true
        }

        if !changed do
            return
        .invalidate()
        .sigSelectionChanged.call(me)
    }

    // Reports whether the row at `index` is checked.
    mtd const isLineChecked(index: u32)->bool
    {
        Debug.assert(!.isVirtual, "virtual lists do not support checked rows")
        Debug.assert(index < .lines.count, "list row index is out of range")
        return .checkModel.isSelected(.lines[index]!.index)
    }

    // Changes the checked state of one checkable row.
    mtd setLineChecked(index: u32, checked: bool = true, notify = true)
    {
        Debug.assert(!.isVirtual, "virtual lists do not support checked rows")
        Debug.assert(index < .lines.count, "list row index is out of range")
        let line = .lines[index]!
        Debug.assert(line.canCheck, "the list row is not checkable")
        if .checkModel.isSelected(line.index) == checked do
            return
        .checkModel.setSelected(line.index, checked)
        .invalidate()
        if notify do
            .sigCheckedChanged.call(me)
    }

    // Changes the checked state of a visible checkable row.
    mtd setLineChecked(line: *ListLine, checked: bool = true, notify = true)
    {
        let result = .idxLineToIdxList.tryFind(line.index)
        Debug.assert(result != null, "the list row is not visible in this control")
        .setLineChecked(result!.value, checked, notify)
    }

    // Clears all checked rows and emits [[Gui.ListCtrl.sigCheckedChanged]] when needed.
    mtd clearCheckedLines(notify = true)
    {
        if .checkModel.isEmpty() do
            return
        .checkModel.clear()
        .invalidate()
        if notify do
            .sigCheckedChanged.call(me)
    }

    // Compute global layout, once all lines have been added
    mtd computeLayout()
    {
        let clientRect = .scrollWnd.paddedClientRect()

        var scrollWidth: f32 = undefined
        if .horizontalExtent > 0 do
            scrollWidth = .horizontalExtent
        elif @isset(.header) do
            scrollWidth = .header.contentWidth()
        else do
            scrollWidth = clientRect.width
        let scrollHeight = .lineCount() * .lineHeight()
        .scrollWnd.setScrollSize(scrollWidth, scrollHeight)
        .invalidate()
    }

    // Returns the effective row height for the current font and configuration.
    mtd lineHeight()->f32
    {
        return .fixedLineHeight != 0 ? .fixedLineHeight : .font().regular!.height + 8
    }

    // Returns the visible row at `index`.
    mtd const lineAt(idx: u32)->#null *ListLine
    {
        Debug.assert(!.isVirtual, "virtual lists do not retain row objects")
        Debug.assert(idx < .lines.count, "list row index is out of range")
        return .lines[idx]
    }

    // Returns the number of visible or virtual rows.
    mtd const lineCount()->u32
    {
        if .isVirtual do
            return .virtualCount
        return cast(u32) .lines.count
    }

    // Returns whether this value has visible check boxes.
    mtd const hasVisibleCheckBoxes()->bool
    {
        if .isVirtual do
            return false

        for line in .lines
        {
            if line!.canCheck do
                return true
        }

        return false
    }

    // Creates an empty root or child row and returns its retained object.
    mtd createLine(parentLine: #null *ListLine)->*ListLine
    {
        Debug.assert(!.isVirtual, "createLine cannot be called on a virtual list")

        if parentLine
        {
            let line = parentLine.lines.allocate()
            line.parent    = parentLine
            line.level     = parentLine.level + 1
            line.index     = .nextLineIndex
            .nextLineIndex += 1
            parentLine.lines.add(line)
            return line
        }

        let line = .toFreeLines.allocate()
        line.index     = .nextLineIndex
        .nextLineIndex += 1
        .idxLineToIdxList.add(line.index, cast(u32) .lines.count)
        .lines.add(line)
        .toFreeLines.add(line)
        return line
    }

    // Creates a row and initializes its first cell.
    #[Swag.Discardable]
    mtd createLine(name: string, icon: Icon = {}, parentLine: #null *ListLine = null)->*ListLine
    {
        let line = .createLine(parentLine)
        line.setItem(0, name, icon)
        return line
    }

    // Removes all retained or virtual rows and clears selection, checks, and focus.
    mtd clear()
    {
        .lines.clear()
        .virtualCount = 0
        .isVirtual    = false
        .idxLineToIdxList.clear()
        .nextLineIndex = 0
        .focusIndex    = Swag.U32.Max
        .selModel.clear()
        .checkModel.clear()
        if @isset(.scrollWnd) do
            .computeLayout()
    }

    // Adds a named column to the list header.
    mtd addColumn(name: string, width: f32 = 100, icon: Icon = {})
    {
        Debug.assert(@isset(.header))
        .header.addColumn(name, width, icon)
    }

    // Changes one header column width.
    mtd setColumnWidth(idx: u32, width: f32)
    {
        Debug.assert(@isset(.header))
        .header.setItemWidth(idx, width)
    }

    // Switches to virtual mode with `count` logical rows.
    // Assign [[onFillVirtualLine]] before painting a non-empty virtual list.
    mtd setVirtualCount(count: u32)
    {
        .clear()
        .isVirtual    = true
        .virtualCount = count
        .computeLayout()
    }

    // Returns the first visible row index, or `Swag.U32.Max` when empty.
    mtd firstVisibleLineIndex()->u32
    {
        let lc  = .lineCount()
        let idx = cast(u32) (.listView.scrollPos.y / .lineHeight())
        if idx >= lc do
            return Swag.U32.Max
        return idx
    }

    // Returns the last visible row index, or `Swag.U32.Max` when empty.
    mtd lastVisibleLineIndex()->u32
    {
        let lc = .lineCount()
        if lc == 0 do
            return Swag.U32.Max

        let viewRect = .listView.paddedClientRect()
        var y        = .listView.scrollPos.y + viewRect.height
        if y <= 0 do
            return cast(u32) (.listView.scrollPos.y / .lineHeight())
        y = Math.max(y - Math.ConstF32.Epsilon, 0)
        let idx = cast(u32) (y / .lineHeight())
        if idx >= lc do
            return cast(u32) lc - 1
        return idx
    }

    // Scrolls enough to make the row at `idx` fully visible.
    mtd ensureVisibleLine(idx: u32)
    {
        Debug.assert(idx < .lineCount())

        let lineHeight    = .lineHeight()
        let viewHeight    = .listView.paddedClientRect().height
        let lineTop       = idx * lineHeight
        let lineBottom    = lineTop + lineHeight
        let sc            = .scrollWnd.scrollPosition()
        let visibleBottom = sc.y + viewHeight

        if lineTop >= sc.y and lineBottom <= visibleBottom do
            return

        var y = lineTop
        if lineBottom > visibleBottom do
            y = lineBottom - viewHeight
        .scrollWnd.setScrollPos(sc.x, y)
    }

    // Returns the retained row with keyboard focus, or `null` in virtual mode or without focus.
    mtd const focusedLine()->#null *ListLine
    {
        if .focusIndex >= .lines.count do
            return null
        return .lines[.focusIndex]
    }

    // Moves keyboard focus to one row without changing selection.
    mtd setFocusedIndex(index: u32, ensureVisible = true)
    {
        Debug.assert(index < .lineCount(), "list row index is out of range")
        if !.isVirtual and .lines[index]!.separator do
            return
        if .focusIndex == index do
            return
        .focusIndex = index
        if ensureVisible do
            .ensureVisibleLine(index)
        .invalidate()
    }

    // Clears the keyboard-focused row without changing selection.
    mtd clearFocusedLine()
    {
        if .focusIndex == Swag.U32.Max do
            return
        .focusIndex = Swag.U32.Max
        .invalidate()
    }

    // Returns the retained rows currently selected, or an empty array in virtual mode.
    mtd const selectedLines()->Array'(#null *ListLine)
    {
        var result: retval
        if .isVirtual or .selModel.isEmpty() do
            return result

        for i in .selModel
        {
            let res = .idxLineToIdxList.tryFind(i)
            if !res do
                continue
            result.add(.lines[res.value])
        }

        return result
    }

    // Returns the retained rows currently checked, or an empty array in virtual mode.
    mtd const checkedLines()->Array'(#null *ListLine)
    {
        var result: retval
        if .isVirtual or .checkModel.isEmpty() do
            return result

        for i in .checkModel
        {
            let res = .idxLineToIdxList.tryFind(i)
            if !res do
                continue
            result.add(.lines[res.value])
        }

        return result
    }

    // Returns a selected line
    // Mostly for singlesel mode
    mtd const selectedLine()->#null *ListLine
    {
        if .isVirtual or .selModel.isEmpty() do
            return null
        let range = .selModel.ranges()[0]
        let res   = .idxLineToIdxList.tryFind(range.start)
        if !res do
            return null
        let idx = res.value
        return .lines[idx]
    }

    private mtd mapIndexes()
    {
        .idxLineToIdxList.clear()
        for l, idx in .lines do
            .idxLineToIdxList.add(l!.index, cast(u32) idx)
    }

    private mtd collectVisibleLines(result: *Array'(#null *ListLine), lines: [..] #null *ListLine)
    {
        for lIt in lines
        {
            result.add(lIt)
            let l = lIt!
            if l.expanded do
                .collectVisibleLines(result, l.lines.toSlice())
        }
    }

    private mtd sort(column: u32, descending: bool, toSort: *Array'(#null *ListLine))
    {
        func sortFunc(column: u32, descending: bool, a, b: #null *ListLine)->s32
        {
            if !a or !b do
                return 0

            let it0   = a.itemAt(column)
            let it1   = b.itemAt(column)
            let sort0 = it0.sortKey.isEmpty() ? &it0.name.raw : &it0.sortKey
            let sort1 = it1.sortKey.isEmpty() ? &it1.name.raw : &it1.sortKey
            var res   = Latin1.compareNatural(dref sort0, dref sort1)
            if descending do
                res *= -1
            return res
        }

        let cb = func|list = me, column, descending|(a, b: #null *ListLine)->s32
        {
            if !a or !b do
                return 0

            let compareLines = list.compareLines
            if compareLines do
                return compareLines(a, b, column, descending)

            if a.parent != b.parent
            {
                if a.isParentOf(b!) do
                    return -1
                if b.isParentOf(a!) do
                    return 1

                var a1 = a!
                var b1 = b!
                while a1.level > b1.level do
                    a1 = a1.parent!
                while b1.level > a1.level do
                    b1 = b1.parent!
                while a1.parent != b1.parent
                {
                    a1 = a1.parent!
                    b1 = b1.parent!
                }

                return sortFunc(column, descending, a1, b1)
            }

            return sortFunc(column, descending, a, b)
        }

        toSort.sort(cb)
    }

    // Sort the list by a given column
    // If 'persistent' is true, then the sorted column will be displayed in the
    // header (if it exists)
    mtd sort(column: u32, descending = false, persistent = false)
    {
        if .isVirtual do
            return

        .sort(column, descending, &.lines)
        .mapIndexes()

        if @isset(.header) and persistent do
            .header.setSortIndicator(column, descending ? .Descending : .Ascending)

        .invalidate()
    }

    // Sort list as before
    mtd sort()
    {
        if @isset(.header) and .header.sortDirection != .None do
            .sort(.header.sortColumn, .header.sortDirection == .Descending)
        else do
            .sort(0, false)
    }

    // Expand the given line
    mtd expand(line: *ListLine)
    {
        if !line.canExpand() or line.expanded do
            return
        line.expanded = true
        .sigExpanded.call(me, line)

        if @isset(.header) and .header.sortDirection != .None do
            .sort(.header.sortColumn, .header.sortDirection == .Descending, &line.lines)

        let res = .idxLineToIdxList.tryFind(line.index)
        if !res do
            return

        var toInsert: Array'(#null *ListLine)
        .collectVisibleLines(&toInsert, line.lines.toSlice())
        if toInsert.count
        {
            .lines.insertAt(cast(u64) (res.value + 1), toInsert.toSlice())
            .mapIndexes()
        }

        .computeLayout()
    }

    // Collapse the given line
    mtd collapse(line: *ListLine)
    {
        if !line.canExpand() or !line.expanded do
            return
        line.expanded = false
        .sigCollapsed.call(me, line)

        var tmp: Array'(#null *ListLine)
        tmp.add(line)

        var removeCount = 0'u32
        while tmp.count
        {
            let toI = tmp.popBack()!
            for l in toI.lines
            {
                removeCount += 1
                if l!.expanded do
                    tmp.add(l)
            }
        }

        // Insert at the right position
        let res = .idxLineToIdxList.tryFind(line.index)
        if !res do
            return
        let idxInsert = res.value
        if removeCount
        {
            .lines.removeAtOrdered(cast(u64) (idxInsert + 1), cast(u64) removeCount)
            .mapIndexes()
        }

        // Update selection
        if .focusIndex >= idxInsert + 1 and .focusIndex < idxInsert + 1 + removeCount
        {
            .unselectAll()
            .focusIndex = idxInsert
            .selectLine(.focusIndex)
        }

        .computeLayout()
    }

    // Collapse all lines
    mtd collapseAll()
    {
        func collapseRec(sl: [..] #null *ListLine)
        {
            for lIt in sl
            {
                let l = lIt!
                l.expanded = false
                collapseRec(l.lines.toSlice())
            }
        }

        for l in .lines
        {
            if l!.expanded do
                .collapse(l!)
        }

        collapseRec(.lines.toSlice())
        .computeLayout()
    }

    // Collapse the given line
    mtd toggleExpand(line: *ListLine)
    {
        if line.expanded do
            .collapse(line)
        else do
            .expand(line)
    }
}
