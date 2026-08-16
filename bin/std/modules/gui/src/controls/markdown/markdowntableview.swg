#global internal

using Core, Pixel

private enum MarkdownTableAlignment
{
    Left
    Center
    Right
}

private struct MarkdownTableCell
{
    view:   *MarkdownInlineView = undefined
    row:    u32
    column: u32
}

#[Swag.Opaque, Swag.NoDoc]
public struct MarkdownTableView
{
    using wnd: Wnd

    owner:        *MarkdownView = undefined
    cells:        Array'MarkdownTableCell
    alignments:   Array'MarkdownTableAlignment
    rowHeights:   Array'f32
    columnCount:  u32
    rowCount:     u32
    layoutWidth:  f32
    layoutHeight: f32
}

private func markdownTableCells(line: string)->Array'String
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

internal impl MarkdownTableView
{
    mtd addRow(parent: *Wnd, cells: const [..] String, row: u32, header: bool)
    {
        for column in .columnCount
        {
            let source = column < @countof(cells) ? cells[column].toString() : ""
            let markup = renderMarkdownInline(source)
            var content: String
            if header do
                content += "<b>"
            content += markup
            if header do
                content += "</b>"
            let view = MarkdownInlineView.create(.owner, parent, content.toString(), .Paragraph)
            view.backgroundStyle = .Transparent
            switch .alignments[column]
            {
            case .Center: view.horizontalAlignment = .Center
            case .Right:  view.horizontalAlignment = .Right
            default:      view.horizontalAlignment = .Left
            }
            .cells.add(MarkdownTableCell{view, row, column})
        }
    }

    mtd layout(width: f32)->f32
    {
        if width <= 0 or !.columnCount do
            return 0
        if .layoutWidth == width do
            return .layoutHeight

        .rowHeights.clear()
        let columnWidth = width / cast(f32) .columnCount
        for row in .rowCount
        {
            var height = 38'f32
            for &cell in .cells where cell.row == row do
                height = Math.max(height, cell.view.preferredHeight(Math.max(columnWidth - 20, 1)) + 12)
            .rowHeights.add(height)
        }

        var y = 0'f32
        for row in .rowCount
        {
            for &cell in .cells where cell.row == row
            {
                let x = cast(f32) cell.column * columnWidth
                cell.view.setPosition({x + 10, y + 4, Math.max(columnWidth - 20, 1), .rowHeights[row] - 8})
            }
            y += .rowHeights[row]
        }

        .layoutWidth  = width
        .layoutHeight = y
        return y
    }

    mtd preferredHeight(width: f32)->f32 => .layout(width)

    func create(owner: *MarkdownView, parent: *Wnd, source: string)->*MarkdownTableView
    {
        let result = Wnd.create'MarkdownTableView(parent, "gui.markdown.table")
        result.owner           = owner
        result.backgroundStyle = .View
        let lines = Tokenize.splitLines(source)
        if lines.count < 2 do
            return result

        let headers    = markdownTableCells(lines[0])
        let separators = markdownTableCells(lines[1])
        result.columnCount = cast(u32) Math.max(headers.count, separators.count)
        for column in result.columnCount
        {
            let separator = column < separators.count ? Latin1.trim(separators[column].toString()) : ""
            let left      = @countof(separator) and separator[0] == ':'
            let right     = @countof(separator) and separator[@countof(separator) - 1] == ':'
            var alignment = MarkdownTableAlignment.Left
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
            let row = markdownTableCells(lines[index])
            result.addRow(result, row.toSlice(), result.rowCount, false)
            result.rowCount += 1
        }
        return result
    }
}

internal impl IWnd for MarkdownTableView
{
    mtd impl onPaint(evt: *PaintEvent)
    {
        let rect    = .clientRect()
        let painter = evt.paintContext.painter
        discard .layout(rect.width)
        if .rowHeights.count do
            painter.fillRect({0, 0, rect.width, .rowHeights[0]}, .themeColors().edit_Bk)

        let border = .themeColors().edit_Border
        var y = 0'f32
        for height in .rowHeights
        {
            painter.fillRect({0, y, rect.width, 1}, border)
            y += height
        }
        painter.fillRect({0, y - 1, rect.width, 1}, border)

        if .columnCount
        {
            let columnWidth = rect.width / cast(f32) .columnCount
            for column in .columnCount + 1 do
                painter.fillRect({cast(f32) column * columnWidth, 0, 1, rect.height}, border)
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
