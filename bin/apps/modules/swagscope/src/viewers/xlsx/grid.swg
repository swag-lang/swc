#global internal
#global namespace Viewers.Xlsx

using Core, Gui, Pixel

private const HeaderWidth  = 64.0'f32
private const HeaderHeight = 28.0'f32
private const ScrollSpan   = 4_194_304.0'f32

// Paints only the visible portion of an authored worksheet, independently of its row address span.
struct Grid
{
    using wnd: Wnd

    late scroll:          *ScrollWnd
    late styles:          *CellStyles
    sheet:                *Sheet?
    rowOffsets:           Array'f64
    columnOffsets:        Array'f32
    originY:              f64
    originX:              f32
    selected:             Address
    hasSelection:         bool
    showHidden:           bool
    keepSelectionVisible: bool
    syncing:              bool
    hovering:             bool
    hovered:              Address     // Cell under the pointer while `hovering`, which the tooltip shows.
    scratch:              RichString
    sigSelected:          SigArray'func||(*Wnd)
}

impl Grid
{
    func create(parent: *Wnd, sheet: *Sheet, styles: *CellStyles, showHidden: bool)->*Grid
    {
        let scroll = Wnd.create'ScrollWnd(parent, "", {})
        scroll.dockStyle = .Center
        with let result = scroll.createView'Grid()
        {
            .scroll          = scroll
            .sheet           = sheet
            .styles          = styles
            .showHidden      = showHidden
            .focusPolicy     = .Tab
            .wndFlags        |= .NoScroll | .NoFocusRing | .ClipChildren
            .backgroundStyle = .View
        }

        scroll.sigScrollPositionChanged += func|grid = result|(_, _, position) { grid.adoptScroll(position) }
        result.buildGeometry()
        return result
    }

    mtd buildGeometry()
    {
        let sheet = .sheet
        if not sheet do
            return
        .columnOffsets.clear()
        .columnOffsets.add(0)
        for column in sheet.columns do
            .columnOffsets.add(.columnOffsets.back() + ((.showHidden or not column.hidden) ? (.showHidden and column.width == 0 ? 64 : column.width) : 0))
        .rowOffsets.resize(cast(u64, sheet.rowCount) + 1)
        .rowOffsets[0] = 0
        var actualRow = 0'u64
        for index in 0 until sheet.rowCount
        {
            var height = sheet.defaultRowHeight
            var hidden = false
            if actualRow < sheet.rows.count and sheet.rows[actualRow].index == index
            {
                height    = sheet.rows[actualRow].height
                hidden    = sheet.rows[actualRow].hidden
                actualRow += 1
            }

            if .showHidden and height == 0 do
                height = Math.max(sheet.defaultRowHeight, 20)
            .rowOffsets[index + 1] = .rowOffsets[index] + ((.showHidden or not hidden) ? cast(f64, height) : 0)
        }

        .originY = .frozenOffset()
        .originX = .frozenWidth()
        .selectAddress({}, reveal: false)
        .syncScroll()
    }

    mtd totalHeight()->f64 => .rowOffsets.isEmpty() ? 0 : .rowOffsets.back()
    mtd totalWidth()->f32  => .columnOffsets.isEmpty() ? 0 : .columnOffsets.back()
    mtd maxOrigin()->f64   => Math.max(Math.max(.totalHeight() + HeaderHeight - .clientRect().height, 0), .frozenOffset())

    mtd frozenOffset()->f64
    {
        if not .sheet or .rowOffsets.count <= .sheet.frozenRows do
            return 0
        return .rowOffsets[.sheet.frozenRows]
    }

    mtd frozenWidth()->f32
    {
        if not .sheet or .columnOffsets.count <= .sheet.frozenColumns do
            return 0
        return .columnOffsets[.sheet.frozenColumns]
    }

    mtd frozenColumn(index: u32)->bool
    {
        if not .sheet do
            return false
        return index < .sheet.frozenColumns
    }

    mtd maxOriginX()->f32 => Math.max(.totalWidth() + HeaderWidth - .clientRect().width, .frozenWidth())

    mtd syncScroll()
    {
        if .syncing or .rowOffsets.isEmpty() do
            return
        .syncing = true
        defer .syncing = false
        .originY = Math.clamp(.originY, .frozenOffset(), .maxOrigin())
        let span = cast(f32, Math.min(.totalHeight() + HeaderHeight, cast(f64, ScrollSpan)))
        .scroll.setScrollSize(.totalWidth() + HeaderWidth, span)
        .originX = Math.clamp(.originX, .frozenWidth(), .maxOriginX())
        let usable = Math.max(span - .clientRect().height, 0)
        let travel = Math.max(.maxOrigin() - .frozenOffset(), 0)
        let y      = travel > 0 ? cast(f32, (.originY - .frozenOffset()) / travel) * usable : 0
        .scroll.setScrollPos(.originX - .frozenWidth(), y)
        .invalidate()
    }

    mtd adoptScroll(position: Math.Point)
    {
        if .syncing do
            return
        let usable = Math.max(.scroll.scrollSize.y - .clientRect().height, 1)
        .keepSelectionVisible = false
        .originY = .frozenOffset() + Math.max(.maxOrigin() - .frozenOffset(), 0) * cast(f64, position.y / usable)
        .originX = .frozenWidth() + position.x
        .invalidate()
    }

    mtd rowAt(y: f64)->u32
    {
        var first = 0'u64
        var last  = .rowOffsets.count - 1
        while first < last
        {
            let middle = first + (last - first) / 2
            if .rowOffsets[middle + 1] <= y do
                first = middle + 1
            else do
                last = middle
        }

        return cast(u32, Math.min(first, .rowOffsets.count - 2))
    }

    mtd nextRow(row: u32)->u32 => .rowAt(.rowOffsets[row + 1])

    mtd cellRect(first, last: Address)->Math.Rectangle
    {
        let x = HeaderWidth + cast(f32, .frozenColumn(first.column) ? .columnOffsets[first.column] : .columnOffsets[first.column] - .originX + .frozenWidth())
        let y = HeaderHeight + cast(f32, first.row < .sheet!.frozenRows ? .rowOffsets[first.row] : .rowOffsets[first.row] - .originY + .frozenOffset())
        return {x, y, .columnOffsets[last.column + 1] - .columnOffsets[first.column], cast(f32, .rowOffsets[last.row + 1] - .rowOffsets[first.row])}
    }

    mtd mergedRange(address: Address)->MergedCells
    {
        for range in .sheet!.merges where address.row >= range.first.row and
                                          address.row <= range.last.row and
                                          address.column >= range.first.column and
                                          address.column <= range.last.column do
            return range
        return MergedCells{address, address}
    }

    internal mtd selectAddress(address: Address, reveal = true)
    {
        let sheet = .sheet
        if not sheet or .rowOffsets.isEmpty() do
            return
        var target = address
        target.row    = Math.min(target.row, sheet.rowCount - 1)
        target.column = Math.min(target.column, cast(u32, sheet.columns.count - 1))
        while target.row < sheet.rowCount and .rowOffsets[target.row + 1] == .rowOffsets[target.row] do
            target.row += 1
        while target.column < sheet.columns.count and .columnOffsets[target.column + 1] == .columnOffsets[target.column] do
            target.column += 1
        if target.row >= sheet.rowCount
        {
            target.row = sheet.rowCount - 1
            while target.row > 0 and .rowOffsets[target.row + 1] == .rowOffsets[target.row] do
                target.row -= 1
        }

        if target.column >= sheet.columns.count
        {
            target.column = cast(u32, sheet.columns.count - 1)
            while target.column > 0 and .columnOffsets[target.column + 1] == .columnOffsets[target.column] do
                target.column -= 1
        }

        .hasSelection = .rowOffsets[target.row + 1] > .rowOffsets[target.row] and
                        .columnOffsets[target.column + 1] > .columnOffsets[target.column] and
                        target.row < sheet.rowCount and
                        target.column < sheet.columns.count
        if not .hasSelection
        {
            .invalidate()
            return
        }

        let range = .mergedRange(target)
        .selected = range.first
        .keepSelectionVisible = reveal
        if reveal
        {
            let rect   = .cellRect(range.first, range.last)
            let client = .clientRect()
            if rect.width > client.width - HeaderWidth do
                .originX = .columnOffsets[range.first.column]
            elif rect.x < HeaderWidth do
                .originX -= HeaderWidth - rect.x
            elif rect.right() > client.width do
                .originX += rect.right() - client.width
            if rect.height > client.height - HeaderHeight do
                .originY = .rowOffsets[range.first.row]
            elif rect.y < HeaderHeight do
                .originY -= HeaderHeight - rect.y
            elif rect.bottom() > client.height do
                .originY += rect.bottom() - client.height
            .syncScroll()
        }

        .sigSelected.call(me)
        .invalidate()
    }

    mtd move(dx, dy: s32)
    {
        if not .hasSelection do
            return
        let range  = .mergedRange(.selected)
        var column = cast(s64, dx > 0 ? range.last.column : range.first.column) + dx
        var row    = cast(s64, dy > 0 ? range.last.row : range.first.row) + dy
        while row >= 0 and
              row < .sheet!.rowCount and
              .rowOffsets[cast(u64, row) + 1] == .rowOffsets[cast(u64, row)] do
            row += dy ? dy : 1
        while column >= 0 and
              column < .sheet!.columns.count and
              .columnOffsets[cast(u64, column) + 1] == .columnOffsets[cast(u64, column)] do
            column += dx ? dx : 1
        if row < 0 or row >= .sheet!.rowCount or column < 0 or column >= .sheet!.columns.count do
            return
        .selectAddress({cast(u32, row), cast(u32, column)})
    }

    internal mtd selectedText()->String
    {
        if not .hasSelection do
            return {}
        if let cell = .sheet!.cellAt(.selected) do
            return cell.text
        return {}
    }

    internal mtd copy()
    {
        if .hasSelection do
            Clipboard.setString(.selectedText())
    }

    mtd addressAt(point: Math.Point)->{address: Address, found: bool}
    {
        if point.x < HeaderWidth or point.y < HeaderHeight or .rowOffsets.isEmpty() do
            return {Address{}, false}
        let localX  = point.x - HeaderWidth
        let frozenX = .frozenWidth()
        let x       = localX < frozenX ? localX : localX + .originX - frozenX
        let localY  = cast(f64, point.y - HeaderHeight)
        let frozen  = .frozenOffset()
        let y       = localY < frozen ? localY : localY + .originY - frozen
        if x >= .totalWidth() or y >= .totalHeight() do
            return {Address{}, false}
        var column = 0'u32
        while column + 1 < .columnOffsets.count and .columnOffsets[column + 1] <= x do
            column += 1
        return {Address{.rowAt(y), column}, true}
    }

    // Shows the text of the cell under the pointer as the tooltip. The pointer moves many times
    // inside one cell, so the tooltip is rebuilt only when it enters another cell or leaves them.
    mtd hover(found: bool, address: Address)
    {
        if found == .hovering and address.row == .hovered.row and address.column == .hovered.column do
            return
        .hovering = found
        .hovered  = address
        .toolTip.clear()
        if not found do
            return

        let range = .mergedRange(address)
        if let cell = .sheet!.cellAt(range.first)
        {
            let text  = cell.text.toString()
            var count = Math.min(text.count, 512)
            while count < text.count and count > 0 and (text[count] & 0xC0) == 0x80 do
                count -= 1
            .toolTip = text[until count]
        }
    }

    mtd drawCell(painter: *Painter, rect: Math.Rectangle, cell: const *Cell, textWidth = -1.0'f32)
    {
        if rect.width <= 0 or rect.height <= 0 or cell.covered do
            return
        let look      = .styles.look(cell.style)
        let available = textWidth >= 0 ? textWidth : rect.width
        let font      = look.font.create(.theme())
        var indent    = 0.0'f32
        if look.alignment.indent
        {
            // Spreadsheet indentation is measured in the Normal style's spaces, not this cell's font.
            let normalFont = .styles.normalFont.create(.theme())
            indent = cast(f32, look.alignment.indent) * Painter.measureStringSnapped("   ", normalFont, deviceScale: .deviceScale())
        }

        let width = Math.max(available - 6 - indent, 0)
        if width <= 0 do
            return

        // The cell's text goes straight into the reused rich string, cut at a character boundary
        // far beyond any visible width, so a paint copies no cell into a string of its own.
        let raw   = cell.text.toString()
        var count = Math.min(raw.count, 4096)
        while count < raw.count and count > 0 and (raw[count] & 0xC0) == 0x80 do
            count -= 1
        .scratch.set(raw[until count])
        if count < raw.count do
            .scratch.append("…")

        // A number too wide for its cell shows as a row of hashes, as a spreadsheet shows it.
        let deviceScale = .deviceScale()
        if cell.numeric and
           not look.alignment.wrap and
           Painter.measureStringSnapped(.scratch.text, font, deviceScale: deviceScale) > width
        {
            let hashWidth = Math.max(Painter.measureStringSnapped("#", font, deviceScale: deviceScale), 1)
            let hashes    = Math.max(cast(u32, Math.floor(width / hashWidth)), 1)
            .scratch.clear()
            for hashes do
                .scratch.append("#")
        }

        .scratch.compute()
        for &chunk in .scratch.chunks do
            chunk.under = look.font.underline ? .Underline : look.font.strike ? .Strikeout : .None
        var format: RichStringFormat
        format.font.regular = font
        format.palette[0]   = Color.fromArgb(look.font.color)
        format.flags        = .Clip
        if look.alignment.wrap do
            format.flags |= .WordWrap
        format.vertAlignment = look.alignment.vertical == .Top ? .Top : look.alignment.vertical == .Bottom ? .Bottom : .Center
        format.horzAlignment = look.alignment.horizontal == .Center ? .Center :
                               look.alignment.horizontal == .Right or (look.alignment.horizontal == .General and cell.numeric) ? .Right : .Left
        if available > rect.width and not .scratch.isEmpty()
        {
            let painted = Painter.measureStringSnapped(.scratch.text, font, deviceScale: deviceScale)
            painter.fillRect(rect.x + 1, rect.y + 1, Math.max(Math.min(painted + 6, available) - 2, 0), Math.max(rect.height - 2, 0), Argb.White)
        }

        let content = Math.Rectangle{rect.x + 3 + (format.horzAlignment == .Right ? 0 : indent), rect.y,
                                     width, rect.height}
        painter.drawRichString(content, &.scratch, format, forceCompute: true)
    }

    mtd paintFills(painter: *Painter, firstRow, lastRow, firstColumn, lastColumn: u32)
    {
        let sheet = unwrap .sheet
        var row   = firstRow
        while row <= lastRow
        {
            let index = sheet.findRow(row)
            if index < sheet.rows.count and sheet.rows[index].index == row
            {
                for cell in sheet.rows[index].cells where cell.column >= firstColumn and
                                                          cell.column <= lastColumn and
                                                          cell.merge == Swag.U32.Max
                {
                    let look = .styles.look(cell.style)
                    if look.fill do
                        painter.fillRect(.cellRect({row, cell.column}, {row, cell.column}), Color.fromArgb(look.fill))
                }
            }

            let next = .nextRow(row)
            if next <= row do
                break
            row = next
        }

        for range in sheet.merges where range.last.row >= firstRow and
                                        range.first.row <= lastRow and
                                        range.last.column >= firstColumn and
                                        range.first.column <= lastColumn
        {
            let rect = .cellRect(range.first, range.last)
            var fill = 0xFFFFFFFF'u32
            if let cell = sheet.cellAt(range.first)
            {
                let look = .styles.look(cell.style)
                if look.fill do
                    fill = look.fill
            }

            painter.fillRect(rect, Color.fromArgb(fill))
            if sheet.showGridLines do
                painter.drawRect(rect, Color.fromArgb(0xFFE1E5E8))
        }
    }

    mtd paintBorders(painter: *Painter, firstRow, lastRow, firstColumn, lastColumn: u32)
    {
        let sheet = unwrap .sheet
        for range in sheet.merges where range.last.row >= firstRow and
                                        range.first.row <= lastRow and
                                        range.last.column >= firstColumn and
                                        range.first.column <= lastColumn
        {
            if let cell = sheet.cellAt(range.first) do
                .styles.look(cell.style).paintBorders(painter, .cellRect(range.first, range.last))
        }

        var row = firstRow
        while row <= lastRow
        {
            let index = sheet.findRow(row)
            if index < sheet.rows.count and sheet.rows[index].index == row
            {
                for cell in sheet.rows[index].cells where cell.column >= firstColumn and cell.column <= lastColumn
                {
                    var mask = 15'u32
                    if cell.merge != Swag.U32.Max
                    {
                        let range = sheet.merges[cell.merge]
                        if not cell.covered do
                            continue
                        mask = (cell.column == range.first.column ? 1'u32 : 0) |
                               (cell.column == range.last.column ? 2'u32 : 0) |
                               (row == range.first.row ? 4'u32 : 0) |
                               (row == range.last.row ? 8'u32 : 0)
                    }

                    .styles.look(cell.style).paintBorders(painter, .cellRect({row, cell.column}, {row, cell.column}), mask)
                }
            }

            let next = .nextRow(row)
            if next <= row do
                break
            row = next
        }
    }
}

impl IWnd for Grid
{
    mtd impl onResizeEvent(_: *ResizeEvent)
    {
        if .syncing do
            return
        .syncScroll()
        if .keepSelectionVisible and .hasSelection do
            .selectAddress(.selected)
    }

    mtd impl onNotifyEvent(evt: *NotifyEvent)
    {
        if evt.kind == .ThemeChanged do
            .invalidate()
        .wnd.IWnd.onNotifyEvent(evt)
    }

    mtd impl onMouseEvent(evt: *MouseEvent)
    {
        let local = .surfaceToLocal(evt.surfacePos)
        let hit   = .addressAt(local)
        switch evt.kind
        {
        case .Pressed where evt.button == .Left:
            if hit.found do
                .selectAddress(hit.address)
            .setFocus()

        case .Move:
            .hover(hit.found, hit.address)

        case .Wheel:
            .keepSelectionVisible = false
            if evt.modifiers.has(.Shift) do
                .originX = Math.max(.originX + (evt.delta.y > 0 ? -64 : 64), 0)
            else do
                .originY = Math.max(.originY + (evt.delta.y > 0 ? -60 : 60), 0)
            .syncScroll()

        default:
            evt.accepted = false
        }
    }

    mtd impl onKeyEvent(evt: *KeyEvent)
    {
        if evt.kind != .Pressed
        {
            evt.accepted = false
            return
        }

        if evt.modifiers == .Control and evt.key == .C
        {
            .copy()
            return
        }

        if evt.modifiers != .None and evt.modifiers != .Control
        {
            evt.accepted = false
            return
        }

        switch evt.key
        {
        case .Left:
            .move(-1, 0)

        case .Right:
            .move(1, 0)

        case .Up:
            .move(0, -1)

        case .Down:
            .move(0, 1)

        case .Home:
            .selectAddress({evt.modifiers == .Control ? 0 : .selected.row, 0})

        case .End:
            .selectAddress({evt.modifiers == .Control ? .sheet!.rowCount - 1 : .selected.row, cast(u32, .sheet!.columns.count - 1)})

        case .PageUp, .PageDown where evt.modifiers == .None:
            let direction = evt.key == .PageUp ? -1.0 : 1.0
            .originY = Math.clamp(.originY + direction * Math.max(.clientRect().height - HeaderHeight, 1), 0, .maxOrigin())
            .selectAddress({Math.max(.rowAt(.originY), .sheet!.frozenRows), .selected.column}, reveal: false)
            .syncScroll()

        default:
            evt.accepted = false
        }
    }

    mtd impl onPaint(evt: *PaintEvent)
    {
        let sheet = .sheet
        if not sheet or .rowOffsets.isEmpty() do
            return
        let painter    = evt.paintContext.painter
        let client     = .clientRect()
        let colors     = .themeColors()
        let headerFont = .theme().createDefaultFont(12)
        let paper      = Color.fromArgb(0xFFFFFFFF)
        let rule       = Color.fromArgb(0xFFE1E5E8)
        painter.fillRect(client, paper)
        let data = Math.Rectangle{HeaderWidth, HeaderHeight, Math.max(client.width - HeaderWidth, 0), Math.max(client.height - HeaderHeight, 0)}
        painter.pushClippingRect(data)
        let firstRow    = .rowAt(.originY)
        let lastRow     = .rowAt(.originY + Math.max(client.height - HeaderHeight, 0))
        var firstColumn = 0'u32
        while firstColumn + 1 < .columnOffsets.count and .columnOffsets[firstColumn + 1] <= .originX do
            firstColumn += 1
        var lastColumn = firstColumn
        while lastColumn + 1 < .columnOffsets.count and .columnOffsets[lastColumn] < .originX + client.width do
            lastColumn += 1
        lastColumn = Math.min(lastColumn, cast(u32, sheet.columns.count - 1))
        var row = firstRow
        if sheet.showGridLines
        {
            row = firstRow
            while row <= lastRow
            {
                let y = HeaderHeight + cast(f32, row < sheet.frozenRows ? .rowOffsets[row] : .rowOffsets[row] - .originY + .frozenOffset())
                painter.drawLine(HeaderWidth, y, Math.min(HeaderWidth + .totalWidth() - .originX, client.width), y, rule)
                let next = .nextRow(row)
                if next <= row do
                    break
                row = next
            }

            let bottom = HeaderHeight + cast(f32, lastRow < sheet.frozenRows ? .rowOffsets[lastRow + 1] : .rowOffsets[lastRow + 1] - .originY + .frozenOffset())
            painter.drawLine(HeaderWidth, bottom, Math.min(HeaderWidth + .totalWidth() - .originX, client.width), bottom, rule)
            for column in firstColumn until lastColumn + 2
            {
                let x = HeaderWidth + (.frozenColumn(column) ? .columnOffsets[column] : .columnOffsets[column] - .originX + .frozenWidth())
                painter.drawLine(x, HeaderHeight, x, Math.min(HeaderHeight + cast(f32, .totalHeight() - .originY), client.height), rule)
            }
        }

        .paintFills(painter, firstRow, lastRow, firstColumn, lastColumn)
        .paintBorders(painter, firstRow, lastRow, firstColumn, lastColumn)

        row = firstRow
        while row <= lastRow
        {
            let index = sheet.findRow(row)
            if index < sheet.rows.count and sheet.rows[index].index == row
            {
                let cells = &sheet.rows[index].cells
                for &cell, position in cells[] where cell.column >= firstColumn and
                                                     cell.column <= lastColumn and
                                                     cell.merge == Swag.U32.Max
                {
                    let rect      = .cellRect({row, cell.column}, {row, cell.column})
                    var available = rect.width
                    let look      = .styles.look(cell.style)
                    if not cell.numeric and
                       not cell.text.isEmpty() and
                       not look.alignment.wrap and
                       (look.alignment.horizontal == .General or look.alignment.horizontal == .Left) and
                       not look.fill and
                       not look.hasBorder()
                    {
                        var right = Math.max(.totalWidth(), .originX + client.width - HeaderWidth)
                        var next  = position + 1
                        while next < cells.count
                        {
                            let nextLook = .styles.look(cells[next].style)
                            if not cells[next].text.isEmpty() or
                               cells[next].merge != Swag.U32.Max or
                               nextLook.fill or
                               nextLook.hasBorder()
                            {
                                right = .columnOffsets[cells[next].column]
                                break
                            }

                            next += 1
                        }

                        available = Math.max(right - .columnOffsets[cell.column], rect.width)
                    }

                    .drawCell(painter, rect, cell, available)
                }
            }

            let next = .nextRow(row)
            if next <= row do
                break
            row = next
        }

        for range in sheet.merges where range.last.row >= firstRow and
                                        range.first.row <= lastRow and
                                        range.last.column >= firstColumn and
                                        range.first.column <= lastColumn
        {
            let rect = .cellRect(range.first, range.last)
            if let cell = sheet.cellAt(range.first) do
                .drawCell(painter, rect, cell)
        }

        if .hasSelection
        {
            let range = .mergedRange(.selected)
            let rect  = .cellRect(range.first, range.last)
            painter.drawRect(rect, colors.arc, 2)
        }

        // Redraw the authored frozen header rows over the scrolling body.  The range is bounded
        // by the workbook's one-million-row limit, but only the small frozen prefix is visited.
        if sheet.frozenRows
        {
            painter.pushClippingRect(data)
            let visibleFrozenRows = Math.min(Math.min(sheet.frozenRows, sheet.rowCount), .rowAt(cast(f64, Math.max(client.height - HeaderHeight, 0))) + 1)
            for row in 0 until visibleFrozenRows
            {
                let rect = Math.Rectangle{HeaderWidth, HeaderHeight + cast(f32, .rowOffsets[row]),
                                          Math.max(client.width - HeaderWidth, 0), cast(f32, .rowOffsets[row + 1] - .rowOffsets[row])}
                painter.fillRect(rect, paper)
                let index = sheet.findRow(row)
                if index < sheet.rows.count and sheet.rows[index].index == row
                {
                    for &cell in sheet.rows[index].cells where cell.merge == Swag.U32.Max and
                                                               (cell.column < sheet.frozenColumns or cell.column >= firstColumn) and
                                                               cell.column <= lastColumn
                    {
                        let cellRect = .cellRect({row, cell.column}, {row, cell.column})
                        let look     = .styles.look(cell.style)
                        if look.fill do
                            painter.fillRect(cellRect, Color.fromArgb(look.fill))
                        look.paintBorders(painter, cellRect)
                        .drawCell(painter, cellRect, cell)
                    }
                }

                if sheet.showGridLines do
                    painter.drawLine(HeaderWidth, rect.bottom(), client.width, rect.bottom(), rule)
            }

            if .hasSelection and .selected.row < sheet.frozenRows
            {
                let range = .mergedRange(.selected)
                painter.drawRect(.cellRect(range.first, range.last), colors.arc, 2)
            }

            painter.popClippingRect()
        }

        // Fixed columns are painted after the scrolling body, just like frozen header rows.
        if sheet.frozenColumns
        {
            painter.pushClippingRect(data)
            let frozenBand = Math.Rectangle{HeaderWidth, HeaderHeight, .frozenWidth(), Math.max(client.height - HeaderHeight, 0)}
            painter.fillRect(frozenBand, paper)
            row = firstRow
            while row <= lastRow
            {
                let index = sheet.findRow(row)
                if index < sheet.rows.count and sheet.rows[index].index == row
                {
                    for &cell in sheet.rows[index].cells where cell.column < sheet.frozenColumns and cell.merge == Swag.U32.Max
                    {
                        let cellRect = .cellRect({row, cell.column}, {row, cell.column})
                        let look     = .styles.look(cell.style)
                        if look.fill do
                            painter.fillRect(cellRect, Color.fromArgb(look.fill))
                        look.paintBorders(painter, cellRect)
                        .drawCell(painter, cellRect, cell)
                    }
                }

                let next = .nextRow(row)
                if next <= row do
                    break
                row = next
            }

            if sheet.showGridLines
            {
                for boundary in 1 until sheet.frozenColumns + 1
                {
                    let x = HeaderWidth + .columnOffsets[boundary]
                    painter.drawLine(x, HeaderHeight, x, client.height, rule)
                }
            }

            if .hasSelection and .frozenColumn(.selected.column)
            {
                let range = .mergedRange(.selected)
                painter.drawRect(.cellRect(range.first, range.last), colors.arc, 2)
            }

            painter.popClippingRect()
        }

        painter.popClippingRect()

        painter.fillRect(0, 0, client.width, HeaderHeight, colors.view_Bk)
        painter.fillRect(0, HeaderHeight, HeaderWidth, client.height - HeaderHeight, colors.view_Bk)
        painter.pushClippingRect({HeaderWidth, 0, Math.max(client.width - HeaderWidth, 0), HeaderHeight})
        for column in firstColumn until lastColumn + 1
        {
            let rect = .cellRect({0, column}, {0, column})
            if rect.width <= 0 do
                continue
            if .hasSelection and column == .selected.column do
                painter.fillRect(rect.x, 0, rect.width, HeaderHeight, colors.selection)
            painter.drawStringCenter(rect.x + rect.width / 2, HeaderHeight / 2, columnName(column), headerFont, colors.softText)
        }

        painter.popClippingRect()
        if sheet.frozenColumns
        {
            painter.pushClippingRect({HeaderWidth, 0, Math.max(client.width - HeaderWidth, 0), HeaderHeight})
            for frozenColumn in 0 until Math.min(sheet.frozenColumns, cast(u32, sheet.columns.count))
            {
                let rect = .cellRect({0, frozenColumn}, {0, frozenColumn})
                if .hasSelection and frozenColumn == .selected.column do
                    painter.fillRect(rect.x, 0, rect.width, HeaderHeight, colors.selection)
                painter.drawStringCenter(rect.x + rect.width / 2, HeaderHeight / 2, columnName(frozenColumn), headerFont, colors.softText)
            }

            painter.popClippingRect()
        }

        painter.pushClippingRect({0, HeaderHeight, HeaderWidth, Math.max(client.height - HeaderHeight, 0)})
        row = firstRow
        while row <= lastRow
        {
            let rect = .cellRect({row, 0}, {row, 0})
            if rect.height > 0
            {
                if .hasSelection and row == .selected.row do
                    painter.fillRect(0, rect.y, HeaderWidth, rect.height, colors.selection)
                let text  = Format.toString("%", row + 1)
                let width = Painter.measureStringSnapped(text, headerFont, deviceScale: .deviceScale())
                painter.drawString(HeaderWidth - width - 8, headerFont.opticalLineTop(rect.y + rect.height / 2), text, headerFont, colors.softText)
            }

            let next = .nextRow(row)
            if next <= row do
                break
            row = next
        }

        painter.popClippingRect()
        if sheet.frozenRows
        {
            painter.pushClippingRect({0, HeaderHeight, HeaderWidth, Math.max(client.height - HeaderHeight, 0)})
            let visibleFrozenRows = Math.min(Math.min(sheet.frozenRows, sheet.rowCount), .rowAt(cast(f64, Math.max(client.height - HeaderHeight, 0))) + 1)
            for frozenRow in 0 until visibleFrozenRows
            {
                let rect = .cellRect({frozenRow, 0}, {frozenRow, 0})
                if .hasSelection and frozenRow == .selected.row do
                    painter.fillRect(0, rect.y, HeaderWidth, rect.height, colors.selection)
                let text  = Format.toString("%", frozenRow + 1)
                let width = Painter.measureStringSnapped(text, headerFont, deviceScale: .deviceScale())
                painter.drawString(HeaderWidth - width - 8, headerFont.opticalLineTop(rect.y + rect.height / 2), text, headerFont, colors.softText)
            }

            painter.popClippingRect()
        }
    }
}
