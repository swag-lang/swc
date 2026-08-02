#global public

using Core

// Configures sizing policies applied by a grid layout.
#[Swag.EnumFlags]
enum GridLayoutFlags
{
    None = 0              // Uses the configured track definitions and keeps the control size.
    FitToContent          // Resizes the control to the laid-out content bounds.
    EqualColumnWidths     // Divides the available width equally between all columns.
    EqualRowHeights       // Divides the available height equally between all rows.
}

// Selects how a grid row or column obtains its size.
enum GridTrackKind
{
    Fixed        // Uses the configured pixel value.
    Content      // Uses the largest preferred size of non-spanning content.
    Fraction     // Receives a weighted fraction of remaining space.
}

// Defines one row or column of a [[GridLayoutCtrl]].
struct GridTrack
{
    kind         = GridTrackKind.Fixed     // Sizing policy.
    value:   f32 = 100                     // Pixel size for `Fixed`, or weight for `Fraction`.
    minimum: f32                           // Minimum track size in logical pixels.
    maximum: f32                           // Maximum track size, or zero for no upper bound.
}

// Arranges child windows in configurable rows, columns, and spanning cells.
struct GridLayoutCtrl
{
    using wnd: Wnd     // Embedded wnd state.

    flags                  = GridLayoutFlags.None     // Active grid sizing options.
    numColumns:        s32                            // Number of columns.
    numRows:           s32                            // Number of rows.
    horizontalSpacing: f32 = 5                        // Gap between adjacent columns.
    verticalSpacing:   f32 = 5                        // Gap between adjacent rows.

    internal
    {
        layout:       Array'(#null *Wnd)     // Window assigned to each cell.
        columnTracks: Array'GridTrack        // Column definitions.
        rowTracks:    Array'GridTrack        // Row definitions.
    }
}

impl IWnd for GridLayoutCtrl
{
    mtd impl onResizeEvent(evt: *ResizeEvent)
    {
        .computeLayout()
        .wnd.IWnd.onResizeEvent(evt)
    }
}

private impl GridLayoutCtrl
{
    mtd ensureStorage()
    {
        Debug.assert(.numColumns > 0 and .numRows > 0)

        let cols  = cast(u64) .numColumns
        let rows  = cast(u64) .numRows
        let cells = cols * rows

        if .layout.count != cells do
            .layout.resize(cells)

        while .columnTracks.count < cols do
            .columnTracks.add({kind: GridTrackKind.Fixed, value: 100})

        while .rowTracks.count < rows do
            .rowTracks.add({kind: GridTrackKind.Fixed, value: 30})

        if .columnTracks.count > cols do
            .columnTracks.resize(cols)
        if .rowTracks.count > rows do
            .rowTracks.resize(rows)
    }

    mtd trackMax(track: GridTrack)->f32
    {
        return track.maximum > 0 ? track.maximum : Swag.F32.Max
    }

    mtd computeTrackSize(track: GridTrack, content: f32)->f32
    {
        var result: retval
        switch track.kind
        {
        case .Fixed:    result = track.value
        case .Content:  result = content
        case .Fraction: result = track.minimum
        }

        result = Math.max(result, track.minimum)
        result = Math.min(result, .trackMax(track))
        return result
    }

    mtd spanH(col, row: s32, child: *Wnd)->s32
    {
        var result: retval = 0
        var idx            = col + (row * .numColumns)
        var c              = col
        while c < .numColumns
        {
            if .layout[idx] != child do
                break
            result += 1
            c      += 1
            idx    += 1
        }

        return result
    }

    mtd spanV(col, row: s32, child: *Wnd)->s32
    {
        var result: retval = 0
        var idx            = col + (row * .numColumns)
        var r              = row
        while r < .numRows
        {
            if .layout[idx] != child do
                break
            result += 1
            r      += 1
            idx    += .numColumns
        }

        return result
    }

    mtd computeContentSizes(columns: bool)->Array'f32
    {
        var result: retval
        let count = columns ? .numColumns : .numRows
        for count do
            result.add(0)

        var done: Array'(#null *Wnd)
        let client = .paddedClientRect()
        for [row] in .numRows
        {
            for [col] in .numColumns
            {
                let idx   = col + (row * .numColumns)
                let child = .layout[idx]
                if !child do
                    continue
                if done.contains(child) do
                    continue
                if !child.isLocallyVisible() do
                    continue
                done.add(child)

                let sh     = .spanH(col, row, child)
                let sv     = .spanV(col, row, child)
                let hint   = child.measure({client.width, client.height})
                let margin = child.layoutMargin()
                if columns
                {
                    if sh == 1 do
                        result[col] = Math.max(result[col], hint.preferred.x + margin.x + margin.z)
                }
                else
                {
                    if sv == 1 do
                        result[row] = Math.max(result[row], hint.preferred.y + margin.y + margin.w)
                }
            }
        }

        return result
    }

    mtd computeTrackSizes(tracks: [..] GridTrack, content: [..] f32, available: f32, spacing: f32, forceEqual: bool)->Array'f32
    {
        var result: retval
        let count = @countof(tracks)
        if !count do
            return result

        let spacingTotal = cast(f32) (count - 1) * spacing
        if forceEqual
        {
            let size = Math.max(available - spacingTotal, 0) / cast(f32) count
            for count do
                result.add(size)
            return result
        }

        var total  = spacingTotal
        var weight = 0'f32
        for [i] in count
        {
            let size = .computeTrackSize(tracks[i], content[i])
            result.add(size)
            total += size
            if tracks[i].kind == GridTrackKind.Fraction
            {
                var trackWeight = 1'f32
                if tracks[i].value > 0 do
                    trackWeight = tracks[i].value
                weight += trackWeight
            }
        }

        let extra = available - total
        if extra > 0 and weight > 0
        {
            var remaining = extra
            while remaining > 0.001
            {
                var activeWeight = 0'f32
                for [i] in count
                {
                    if tracks[i].kind == GridTrackKind.Fraction and result[i] < .trackMax(tracks[i]) do
                        activeWeight += tracks[i].value > 0 ? tracks[i].value : 1
                }

                if activeWeight <= 0 do
                    break

                var distributed = 0'f32
                for [i] in count
                {
                    if tracks[i].kind != GridTrackKind.Fraction or result[i] >= .trackMax(tracks[i]) do
                        continue
                    let w      = tracks[i].value > 0 ? tracks[i].value : 1
                    let share  = remaining * w / activeWeight
                    let actual = Math.min(share, .trackMax(tracks[i]) - result[i])
                    result[i]   += actual
                    distributed += actual
                }

                if distributed <= 0.001 do
                    break
                remaining -= distributed
            }
        }
        elif extra < 0
        {
            var shrinkPool = 0'f32
            for [i] in count do
                shrinkPool += Math.max(result[i] - tracks[i].minimum, 0)

            if shrinkPool > 0
            {
                let shortage = -extra
                for [i] in count
                {
                    let shrink = Math.max(result[i] - tracks[i].minimum, 0)
                    result[i] -= shortage * shrink / shrinkPool
                    result[i] = Math.max(result[i], tracks[i].minimum)
                }
            }
        }

        return result
    }

    mtd trackOffset(sizes: [..] f32, idx: s32, spacing: f32)->f32
    {
        var result: retval
        for [i] in idx
        {
            result += sizes[i]
            result += spacing
        }

        return result
    }

    mtd trackSpanSize(sizes: [..] f32, idx, span: s32, spacing: f32)->f32
    {
        var result: retval
        for [i] in span
        {
            if i do
                result += spacing
            result += sizes[idx + i]
        }

        return result
    }
}

impl GridLayoutCtrl
{
    // Creates an empty grid with `numColumns` columns and `numRows` rows.
    func create(parent: *Wnd, numColumns, numRows: s32, position: Math.Rectangle = {})->*GridLayoutCtrl
    {
        Debug.assert(numColumns > 0 and numRows > 0)

        let res = Wnd.create'GridLayoutCtrl(parent, position)
        res.numColumns = numColumns
        res.numRows    = numRows
        res.ensureStorage()

        return res
    }

    // Recomputes track sizes and arranges every assigned child.
    mtd computeLayout()
    {
        if !.children.count do
            return
        .ensureStorage()

        let client     = .paddedClientRect()
        let colContent = .computeContentSizes(true)
        let rowContent = .computeContentSizes(false)
        let colWidths  = .computeTrackSizes(.columnTracks.toSlice(), colContent.toSlice(), client.width, .horizontalSpacing, .flags.has(.EqualColumnWidths))
        let rowHeights = .computeTrackSizes(.rowTracks.toSlice(), rowContent.toSlice(), client.height, .verticalSpacing, .flags.has(.EqualRowHeights))

        var done: Array'(#null *Wnd)
        var maxW, maxH = 0'f32
        for [row] in .numRows
        {
            for [col] in .numColumns
            {
                let idx   = col + (row * .numColumns)
                let child = .layout[idx]
                if !child do
                    continue
                if done.contains(child) do
                    continue
                if !child.isLocallyVisible() do
                    continue

                done.add(child)
                let sh = .spanH(col, row, child)
                let sv = .spanV(col, row, child)

                var rect = Math.Rectangle{
                    client.x + .trackOffset(colWidths.toSlice(), col, .horizontalSpacing),
                    client.y + .trackOffset(rowHeights.toSlice(), row, .verticalSpacing),
                    .trackSpanSize(colWidths.toSlice(), col, sh, .horizontalSpacing),
                    .trackSpanSize(rowHeights.toSlice(), row, sv, .verticalSpacing)}

                rect.applyPadding(child.layoutMargin())
                child.arrange(rect)
                maxW = Math.max(maxW, rect.right() + .padding.z)
                maxH = Math.max(maxH, rect.bottom() + .padding.w)
            }
        }

        if .flags.has(.FitToContent)
        {
            .position.width  = maxW
            .position.height = maxH
            .preferredSize   = {maxW, maxH}
        }
    }

    // Sets one column to a fixed pixel size.
    mtd setColumnSize(column: s32, size: f32)
    {
        .ensureStorage()
        Debug.assert(column >= 0 and column < .numColumns)
        .setColumnTrack(column, GridTrackKind.Fixed, size)
    }

    // Sets one row to a fixed pixel size.
    mtd setRowSize(row: s32, size: f32)
    {
        .ensureStorage()
        Debug.assert(row >= 0 and row < .numRows)
        .setRowTrack(row, GridTrackKind.Fixed, size)
    }

    // Configures one column track.
    mtd setColumnTrack(column: s32, kind: GridTrackKind, value: f32 = 1, minimum: f32 = 0, maximum: f32 = 0)
    {
        .ensureStorage()
        Debug.assert(column >= 0 and column < .numColumns)
        Debug.assert(minimum >= 0 and (maximum == 0 or maximum >= minimum))
        .columnTracks[column] = {kind: kind, value: value, minimum: minimum, maximum: maximum}
    }

    // Configures one row track.
    mtd setRowTrack(row: s32, kind: GridTrackKind, value: f32 = 1, minimum: f32 = 0, maximum: f32 = 0)
    {
        .ensureStorage()
        Debug.assert(row >= 0 and row < .numRows)
        Debug.assert(minimum >= 0 and (maximum == 0 or maximum >= minimum))
        .rowTracks[row] = {kind: kind, value: value, minimum: minimum, maximum: maximum}
    }

    // Assigns `child` to a cell and optional column/row span.
    //
    // Reassigning a child moves it from its previous cells. Overlap with another assigned
    // child is rejected.
    mtd setCell(child: *Wnd, column, row: s32, columnSpan, rowSpan: s32 = 1)
    {
        .ensureStorage()
        Debug.assert(child.parent == me)
        Debug.assert(column >= 0 and row >= 0)
        Debug.assert(column + columnSpan <= .numColumns and row + rowSpan <= .numRows)
        Debug.assert(columnSpan > 0 and rowSpan > 0)

        for [idx] in .layout.count
        {
            if .layout[idx] == child do
                .layout[idx] = null
        }

        for [i] in columnSpan
        {
            var x = column + (row * .numColumns)
            x += i
            for [j] in rowSpan
            {
                let x1 = x + (j * .numColumns)
                Debug.assert(!.layout[x1], "grid cell is already assigned")
                .layout[x1] = child
            }
        }
    }
}
