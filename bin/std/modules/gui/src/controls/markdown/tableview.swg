#global internal
#global namespace Markdown

using Core, Pixel

private enum TableAlignment
{
    Left
    Center
    Right
}

private struct TableCell
{
    view:   *InlineView = undefined
    row:    u32
    column: u32
}

#[Swag.Opaque, Swag.NoDoc]
public struct TableView
{
    using wnd: Wnd

    owner:        *View = undefined
    cells:        Array'TableCell
    alignments:   Array'TableAlignment
    rowHeights:   Array'f32
    columnWidths: Array'f32
    tableWidth:   f32
    columnCount:  u32
    rowCount:     u32
    layoutWidth:  f32
    layoutHeight: f32
}

private const MinColumnWidth = 48'f32
private const CellPadding = 20'f32

private func parseTableCells(line: string)->Array'String
{
    var result: retval
    let trimmed = Latin1.trim(line)
    var start   = 0'u64
    var end     = @countof(trimmed)
    if start < end and trimmed[start] == '|' do
        start += 1
    if end > start and trimmed[end - 1] == '|' do
        end -= 1

    var cell: String
    var index = start
    while index < end
    {
        if trimmed[index] == '\\' and index + 1 < end and trimmed[index + 1] == '|'
        {
            cell  += "|"
            index += 2
            continue
        }

        if trimmed[index] == '|'
        {
            result.add(String.from(Latin1.trim(cell.toString())))
            cell.clear()
            index += 1
            continue
        }

        cell  += trimmed[index until index + 1]
        index += 1
    }

    result.add(String.from(Latin1.trim(cell.toString())))
    return result
}

impl TableView
{
    mtd clearSearchHighlight()
    {
        for &cell in .cells do
            cell.view.clearSearchHighlight()
    }

    mtd highlightText(text: string)->bool
    {
        .clearSearchHighlight()
        for &cell in .cells where cell.view.highlightText(text) do
            return true
        return false
    }

    mtd addRow(parent: *Wnd, cells: const [..] String, row: u32, header: bool)
    {
        for column in .columnCount
        {
            let source = column < @countof(cells) ? cells[column].toString() : ""
            let markup = renderInline(source)
            var content: String
            if header do
                content += "<b>"
            content += markup
            if header do
                content += "</b>"
            let view = InlineView.create(.owner, parent, content.toString(), .Paragraph)
            view.backgroundStyle = .Transparent
            switch .alignments[column]
            {
            case .Center: view.horizontalAlignment = .Center
            case .Right:  view.horizontalAlignment = .Right
            default:      view.horizontalAlignment = .Left
            }

            .cells.add(TableCell{view, row, column})
        }
    }

    mtd columnOffset(column: u32)->f32
    {
        var result = 0'f32
        for one in column do
            result += .columnWidths[one]
        return result
    }

    mtd layout(width: f32)->f32
    {
        if width <= 0 or !.columnCount do
            return 0
        if .layoutWidth == width do
            return .layoutHeight

        // Columns take their natural content width; only when the table would overflow the
        // document column do the wide columns shrink, and columns at the floor keep it.
        .columnWidths.clear()
        .columnWidths.resize(.columnCount)
        for &cell in .cells do
            .columnWidths[cell.column] = Math.max(.columnWidths[cell.column], cell.view.naturalWidth() + CellPadding)

        var total = 0'f32
        for &column in .columnWidths
        {
            column[] = Math.max(column[], MinColumnWidth)
            total    += column[]
        }

        if total > width
        {
            var flexible = 0'f32
            for column in .columnWidths where column > MinColumnWidth do
                flexible += column - MinColumnWidth
            if flexible > 0
            {
                let excess = Math.min(total - width, flexible)
                for &column in .columnWidths where column[] > MinColumnWidth do
                    column[] -= (column[] - MinColumnWidth) / flexible * excess
            }

            total = 0
            for column in .columnWidths do
                total += column
        }

        .tableWidth = Math.min(total, width)
        .rowHeights.clear()
        for row in .rowCount
        {
            var height = 38'f32
            for &cell in .cells where cell.row == row do
                height = Math.max(height, cell.view.preferredHeight(Math.max(.columnWidths[cell.column] - CellPadding, 1)) + 12)
            .rowHeights.add(height)
        }

        var y = 0'f32
        for row in .rowCount
        {
            for &cell in .cells where cell.row == row
            {
                let x = .columnOffset(cell.column)
                cell.view.setPosition({x + 10, y + 4, Math.max(.columnWidths[cell.column] - CellPadding, 1), .rowHeights[row] - 8})
            }

            y += .rowHeights[row]
        }

        .layoutWidth  = width
        .layoutHeight = y
        return y
    }

    mtd preferredHeight(width: f32)->f32 => .layout(width)

    func create(owner: *View, parent: *Wnd, source: string)->*TableView
    {
        let result = Wnd.create'TableView(parent, "gui.markdown.table")
        result.owner           = owner
        result.backgroundStyle = .View
        let lines = Tokenize.splitLines(source)
        if lines.count < 2 do
            return result

        let headers    = parseTableCells(lines[0])
        let separators = parseTableCells(lines[1])
        result.columnCount = cast(u32) Math.max(headers.count, separators.count)
        for column in result.columnCount
        {
            let separator = column < separators.count ? Latin1.trim(separators[column].toString()) : ""
            let left      = @countof(separator) and separator[0] == ':'
            let right     = @countof(separator) and separator[@countof(separator) - 1] == ':'
            var alignment = TableAlignment.Left
            if left and right do
                alignment = .Center
            elif right do
                alignment = .Right
            result.alignments.add(alignment)
        }

        result.addRow(result, headers.toSlice(), 0, true)
        result.rowCount = 1
        for index in 2 until lines.count
        {
            if !@countof(Latin1.trim(lines[index])) do
                continue
            let row = parseTableCells(lines[index])
            result.addRow(result, row.toSlice(), result.rowCount, false)
            result.rowCount += 1
        }

        return result
    }
}

impl IWnd for TableView
{
    mtd impl onPaint(evt: *PaintEvent)
    {
        let rect    = .clientRect()
        let painter = evt.paintContext.painter
        discard .layout(rect.width)
        if .rowHeights.count do
            painter.fillRect({0, 0, .tableWidth, .rowHeights[0]}, .themeColors().edit_Bk)

        let border = .themeColors().edit_Border
        var y      = 0'f32
        for height in .rowHeights
        {
            painter.fillRect({0, y, .tableWidth, 1}, border)
            y += height
        }

        painter.fillRect({0, y - 1, .tableWidth, 1}, border)

        if .columnCount
        {
            for column in .columnCount do
                painter.fillRect({.columnOffset(column), 0, 1, rect.height}, border)
            painter.fillRect({.tableWidth - 1, 0, 1, rect.height}, border)
        }
    }

    mtd impl onThemeEvent(evt: *ThemeEvent)
    {
        for &cell in .cells do
            cell.view.layoutWidth = 0
        .layoutWidth = 0
        .invalidate()
    }
}
