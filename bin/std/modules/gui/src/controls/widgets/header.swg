#global public

using Core, Pixel

// Selects header background and border presentation.
enum HeaderForm
{
    Transparent     // Draws only the bottom separator.
    Flat            // Draws a square background and border.
    Round           // Draws a rounded background and border.
}

// Describes one column displayed by a header.
struct HeaderItem
{
    public
    {
        name:              RichString     // Displayed column label.
        icon:              Icon           // Optional icon drawn before the label.
        isResizable = true                // Whether the trailing separator can resize the column.
        isClickable = true                // Whether the column can emit click actions.
        reservesIconSpace: bool           // Whether list rows reserve the header icon column.
    }

    width:        f32     // Effective width in logical units.
    minimumWidth: f32     // Inclusive minimum width.
    maximumWidth: f32     // Inclusive maximum width, or zero when unbounded.
    column:       u32     // Stable logical column identifier.
}

// Configures header interaction.
#[Swag.EnumFlags]
enum HeaderFlags
{
    None = 0       // Disables column click actions and separator-based resizing.
    Clickable      // Enables click actions for individually clickable columns.
    Separators     // Draws column separators and lets resizable columns be dragged.
}

// Indicates the direction displayed by a column sort marker.
enum HeaderSortDirection
{
    None           // No sort marker is displayed.
    Ascending      // Displays an ascending sort marker.
    Descending     // Displays a descending sort marker.
}

// Displays named, optionally sortable and resizable columns.
struct Header
{
    public
    {
        using wnd: Wnd     // Embedded window behavior and presentation.

        form = HeaderForm.Flat                              // Background and border presentation.
        itemPadding:      f32 = 5                           // Horizontal inset applied to each item label.
        sigLayoutChanged: SigArray'func||(*Header)          // Emitted after an effective column width changes.
        sigColumnClicked: SigArray'func||(*Header, u32)     // Emitted after the user clicks a column.

        // The columns the header shows, and which one it sorts on. Add columns through the methods
        // so the layout and the owning list stay in step.
        readonly
        {
            flags         = HeaderFlags.Clickable | .Separators     // Active interaction and separator options.
            items: ArrayPtr'HeaderItem                              // Columns in display order.
            sortColumn    = Swag.U32.Max                            // Logical column carrying the sort marker.
            sortDirection = HeaderSortDirection.None                // Direction of the sort marker.
        }
    }

    // Hover and drag state of one gesture over the header.
    hotIdx = Swag.U32.Max     // Column under the mouse.
    hotSeparator:  bool       // Whether the mouse is over a separator.
    moving:        bool       // Whether a separator drag is in progress.
    clicked:       bool       // Whether a click gesture started on a column.
    correctMoving: f32        // Grab offset inside the separator, kept for the drag.
}

impl IWnd for Header
{
    // Reports the room the configured columns occupy, and the height of the bar.
    //
    // The width is what the columns are set to, not what their labels need: a column width
    // is chosen by the owning list or dragged by the reader, and a column deliberately
    // narrower than its label is a state the header supports rather than a misfit. Use
    // [[Gui.Header.setItemMinimumWidth]] to keep a label from being squeezed out.
    mtd impl measureContent(available: Math.Point)->Math.Point
    {
        discard available

        let metrics = .themeMetrics()
        return {.contentWidth() + .padding.z, metrics.header_Height}
    }

    mtd paintItem(bc: PaintContext, item: *HeaderItem, idx: u32, x: f32)
    {
        let painter = bc.painter

        let clientRect = .clientRect()
        var labelPos   = clientRect
        labelPos.x     = x
        labelPos.width = item.width

        let theme   = .theme()
        let metrics = .themeMetrics()
        let colors  = .themeColors()

        if .hotIdx == idx and !.hotSeparator
        {
            var labelPosBk = labelPos
            labelPosBk.x     -= (metrics.header_Separator * 0.5)
            labelPosBk.width += metrics.header_Separator
            theme.drawSubRect(painter, labelPosBk, &theme.rects.selectionBox_Bk, .clicked ? colors.headerItem_ClickedBk : colors.headerItem_HotBk)
        }

        labelPos.moveLeft(.itemPadding)

        var colorText: Color
        switch
        {
        case bc.isDisabled:  colorText = colors.headerItem_DisabledText
        case idx == .hotIdx: colorText = colors.headerItem_HotText
        default:             colorText = colors.headerItem_Text
        }

        // Sort mark
        if .sortDirection != .None and .sortColumn == item.column
        {
            // The marker points the way the column is ordered: up for ascending, down for
            // descending. It named the two the right way round and drew them the wrong way
            // round, so a column sorted A to Z carried the marker of a column sorted Z to A.
            let glyph = .sortDirection == .Ascending ? ThemeIcons.ChevronUp : ThemeIcons.ChevronDown
            let icon  = theme.icon(glyph, metrics.chevron_Size)
            if labelPos.width > icon.sizeX
            {
                var sortPos = labelPos
                sortPos.x = Math.max(sortPos.x, sortPos.right() - icon.sizeX)
                sortPos.y = opticalTop(.font(), sortPos.vertCenter(), icon.sizeY)
                icon.paint(painter, sortPos.x, sortPos.y, colorText)
                labelPos.width -= icon.sizeX
            }
        }

        var format: RichStringFormat
        theme.setTextColors(&format, colorText)
        format.horzAlignment = .Left
        format.vertAlignment = .Center
        format.flags         = .Clip
        format.font          = .font()
        Theme.drawIconText(painter, labelPos, item.icon, &item.name, format, metrics.iconText_Margin)
    }

    mtd impl onPaint(evt: *PaintEvent)
    {
        let painter = evt.paintContext.painter
        let theme   = .theme()
        let metrics = .themeMetrics()
        let colors  = .themeColors()
        let rects   = .themeRects()

        // Background bar
        var clientRect = .clientRect()
        clientRect.offset(.scrollPos)
        switch .form
        {
        case .Flat:        theme.drawSubRect(painter, clientRect, &rects.header_FlatBk, colors.header_Bk)
        case .Round:       theme.drawSubRect(painter, clientRect, &rects.header_RoundBk, colors.header_Bk)
        case .Transparent: painter.drawLine(clientRect.x, clientRect.bottom() - 1, clientRect.right(), clientRect.bottom() - 1, colors.headerItem_Separator, 1)
        }

        // Keep the clip in the same local coordinate space as the item geometry. A presented
        // ancestor can paint this subtree into an off-screen layer whose origin differs from
        // the surface origin; an absolute surface clip would then reject the header contents.
        painter.pushClippingRect(.paddedClientRect())
        defer painter.popClippingRect()

        // Paint all except selected one, which will be painted last
        clientRect = .paddedClientRect()
        clientRect.offset(.scrollPos)
        var x = .padding.x
        for item, idx in .items
        {
            @assert(item != null)
            .paintItem(evt.paintContext, item, cast(u32) idx, x)
            x += item.width

            if .flags.has(.Separators)
            {
                var rect = clientRect
                rect.x = x + (metrics.header_Separator * 0.5)
                painter.drawLine(rect.x, rect.y, rect.x, rect.bottom(), colors.headerItem_Separator, 1)
            }

            x += metrics.header_Separator
        }
    }

    mtd impl onMouseEvent(evt: *MouseEvent)
    {
        if evt.kind == .Released and evt.button == .Left
        {
            if .clicked and !.sigColumnClicked.isEmpty()
            {
                let {hit, ?} = .hitTest(evt.surfacePos)
                if hit == .hotIdx do
                    .sigColumnClicked.call(me, .items[.hotIdx]!.column)
            }

            if .moving or .clicked
            {
                .moving, .clicked = false
                .releaseMouse()
                .invalidate()
            }
        }

        if !.moving and !.clicked
        {
            let {hitr, sep} = .hitTest(evt.surfacePos)
            var hit         = hitr

            // Hot, if not a separator, is disabled if item is not clickable
            if hit != Swag.U32.Max
            {
                if !.flags.has(.Clickable) and !sep do
                    hit = Swag.U32.Max
                elif !.items[hit]!.isClickable do
                    hit = Swag.U32.Max
            }

            if hit != .hotIdx
            {
                .hotIdx = hit
                .invalidate()
            }

            if .hotSeparator != sep
            {
                .hotSeparator = sep
                .invalidate()
            }

            if .hotSeparator do
                .cursor = Cursor.from(CursorShape.ResizeHorizontal)
            else do
                .cursor.clear()
        }

        if .hotIdx == Swag.U32.Max
        {
            evt.accepted = false
            return
        }

        switch evt.kind
        {
        case .Move:
            if .moving
            {
                var pos = .surfaceToLocal(evt.surfacePos)
                pos += .scrollPos.x
                var move = pos.x - .itemPositionAt(.hotIdx) + .padding.x
                move -= .correctMoving
                .setItemWidth(.hotIdx, move)
            }

        case .Leave:
            if .hotIdx != Swag.U32.Max
            {
                .hotIdx = Swag.U32.Max
                .invalidate()
            }

        case .Pressed:
            if evt.button == .Left and .hotIdx != Swag.U32.Max
            {
                if .hotSeparator
                {
                    .moving = true
                    var pos = .surfaceToLocal(evt.surfacePos)
                    pos            += .scrollPos.x
                    .correctMoving = pos.x - .itemPositionAt(.hotIdx) + .padding.x
                    .correctMoving -= .itemWidthAt(.hotIdx)
                    .captureMouse()
                }
                elif .items[.hotIdx]!.isClickable
                {
                    .clicked = true
                    .captureMouse()
                    .invalidate()
                }
            }
        }
    }
}

private impl Header
{
    mtd hitTest(surfacePos: Math.Point)->{ idx: u32, sep: bool }
    {
        let metrics = .themeMetrics()
        var pos     = .surfaceToLocal(surfacePos)
        pos += .scrollPos.x
        var x = .padding.x
        for itemIt, idx in .items
        {
            let item = itemIt!
            if pos.x >= x and pos.x < x + item.width do
                return {cast(u32) idx, false}
            x += item.width
            if .flags.has(.Separators) and pos.x >= x and pos.x <= x + metrics.header_Separator and item.isResizable do
                return {cast(u32) idx, true}
            x += metrics.header_Separator
        }

        return {Swag.U32.Max, false}
    }
}

impl Header
{
    // Shows a sort direction for one logical column.
    mtd setSortIndicator(column: u32, direction: HeaderSortDirection)
    {
        Debug.assert(column < .items.count)
        Debug.assert(direction != .None)
        .sortColumn    = column
        .sortDirection = direction
        .invalidate()
    }

    // Removes the current sort marker.
    mtd clearSortIndicator()
    {
        if .sortDirection == .None do
            return
        .sortColumn    = Swag.U32.Max
        .sortDirection = .None
        .invalidate()
    }

    // Creates an empty header using the current theme height by default.
    #[Swag.Discardable]
    func create(parent: *Wnd, position: Math.Rectangle = {}, id: #null WndId = null)->*Header
    {
        Debug.assert(parent != null)

        let metrics = parent.themeMetrics()
        var pos     = position
        if pos.height == 0 do
            pos.height = metrics.header_Height
        let result = Wnd.create'Header(parent, null, pos, id)
        result.padding = metrics.header_Padding
        return result
    }

    // Appends a logical column with a non-negative initial width.
    #[Swag.Discardable]
    mtd addColumn(name: string, width = 100'f32, icon: Icon = {})->*HeaderItem
    {
        let item = .items.allocate()
        item.name   = name
        item.icon   = icon
        item.width  = Math.max(width, 0)
        item.column = cast() .items.count
        .items.add(item)
        .invalidate()
        return item
    }

    // Returns the column at one display-order index.
    mtd const itemAt(index: u32)->*HeaderItem
    {
        Debug.assert(index < .items.count)
        return .items[index]!
    }

    // Returns the item for one logical column identifier.
    mtd const itemForColumn(column: u32)->*HeaderItem
    {
        Debug.assert(column < .items.count)

        for item in .items
        {
            if item!.column == column do
                return item!
        }

        unreachable
    }

    // Returns the effective width at one display-order index.
    mtd const itemWidthAt(index: u32)->f32
    {
        Debug.assert(index < .items.count)
        return .itemWidthForColumn(.items[index]!.column)
    }

    // Returns the effective width for one logical column identifier.
    mtd const itemWidthForColumn(column: u32)->f32
    {
        Debug.assert(column < .items.count)

        for itemIt in .items
        {
            let item = itemIt!
            if item.column == column do
                return item.width
        }

        return 0
    }

    // Returns the leading position at one display-order index.
    mtd itemPositionAt(index: u32)->f32
    {
        Debug.assert(index < cast(u32) .items.count)
        return .itemPositionForColumn(.items[index]!.column)
    }

    // Returns the leading position for one logical column identifier.
    mtd itemPositionForColumn(column: u32)->f32
    {
        Debug.assert(column < .items.count)

        var x = .padding.x
        let m = .themeMetrics().header_Separator
        for itemIt, i in .items
        {
            let item = itemIt!
            if item.column == column do
                return x
            x += item.width + m
        }

        return 0
    }

    // Returns the complete width occupied by columns, separators, and leading padding.
    mtd contentWidth()->f32
    {
        if .items.isEmpty() do
            return .padding.x

        var w = .itemPositionAt(cast(u32) .items.count - 1)
        w += .items.back()!.width
        w += .themeMetrics().header_Separator
        return w
    }

    // Sets an item width by display-order index and applies its configured limits.
    mtd setItemWidth(index: u32, width: f32)
    {
        Debug.assert(index < .items.count)
        .setItemWidthForColumn(.items[index]!.column, width)
    }

    // Sets an item width by logical column identifier and applies its configured limits.
    mtd setItemWidthForColumn(column: u32, width: f32)
    {
        Debug.assert(column < .items.count)

        let item = .itemForColumn(column)!
        var move = Math.max(width, item.minimumWidth)
        if item.maximumWidth > 0 do
            move = Math.min(move, item.maximumWidth)
        if item.width == move do
            return
        item.width = move
        .sigLayoutChanged.call(me)
        .invalidate()
    }

    // Configures inclusive width limits by display-order index and clamps the current width.
    // A maximum of zero leaves the column unbounded.
    mtd setItemWidthLimits(index: u32, minimum: f32 = 0, maximum: f32 = 0)
    {
        Debug.assert(index < .items.count)
        Debug.assert(minimum >= 0)
        Debug.assert(maximum == 0 or maximum >= minimum)
        let item = .items[index]!
        item.minimumWidth = minimum
        item.maximumWidth = maximum
        .setItemWidth(index, item.width)
    }

    // Adds and removes interaction or separator options and clears transient state they disable.
    mtd updateFlags(add: HeaderFlags = .None, remove = HeaderFlags.None)
    {
        .flags.add(add)
        .flags.remove(remove)
        if !.flags.has(.Separators)
        {
            if .moving
            {
                .moving = false
                .releaseMouse()
            }

            .hotSeparator = false
            .cursor.clear()
        }

        if !.flags.has(.Clickable) and !.hotSeparator do
            .hotIdx = Swag.U32.Max
        .invalidate()
    }
}
