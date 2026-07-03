#global public
using Core

#[Swag.EnumFlags]
enum GridLayoutCtrlFlags
{
    Zero               = 0
    AdaptSizeToContent
    AdaptColWidth
    AdaptRowHeight
}

enum GridTrackKind
{
    Fixed
    Content
    Fraction
    Fill
}

struct GridTrack
{
    kind       = GridTrackKind.Fixed
    value:     f32 = 100
    min:       f32
    max:       f32
}

struct GridLayoutCtrl
{
    using wnd:          Wnd

    gridLayoutFlags     = GridLayoutCtrlFlags.Zero
    numColumns:         s32
    numRows:            s32
    spacingHorz:        f32 = 5
    spacingVert:        f32 = 5

    layout:             Array'*Wnd
    colSizes:           Array'f32
    rowSizes:           Array'f32
    colTracks:          Array'GridTrack
    rowTracks:          Array'GridTrack
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

        let cols = cast(u64) .numColumns
        let rows = cast(u64) .numRows
        let cells = cols * rows

        if .layout.count != cells do
            .layout.resize(cells)

        while .colSizes.count < cols do
            .colSizes.add(100)
        while .rowSizes.count < rows do
            .rowSizes.add(30)
        if .colSizes.count > cols do
            .colSizes.resize(cols)
        if .rowSizes.count > rows do
            .rowSizes.resize(rows)

        while .colTracks.count < cols
        {
            let idx = .colTracks.count
            .colTracks.add({kind: GridTrackKind.Fixed, value: .colSizes[idx]})
        }

        while .rowTracks.count < rows
        {
            let idx = .rowTracks.count
            .rowTracks.add({kind: GridTrackKind.Fixed, value: .rowSizes[idx]})
        }

        if .colTracks.count > cols do
            .colTracks.resize(cols)
        if .rowTracks.count > rows do
            .rowTracks.resize(rows)
    }

    mtd trackMax(track: GridTrack)->f32
    {
        return track.max > 0 ? track.max : Swag.F32.Max
    }

    mtd computeTrackSize(track: GridTrack, content: f32)->f32
    {
        var result: retval
        switch track.kind
        {
        case Fixed:
            result = track.value
        case Content:
            result = content
        case Fraction, Fill:
            result = track.min
        }

        result = Math.max(result, track.min)
        result = Math.min(result, .trackMax(track))
        return result
    }

    mtd spanH(col, row: s32, child: *Wnd)->s32
    {
        var result: retval = 0
        var idx = col + (row * .numColumns)
        var c = col
        while c < .numColumns
        {
            if .layout[idx] != child do
                break
            result += 1
            c += 1
            idx += 1
        }

        return result
    }

    mtd spanV(col, row: s32, child: *Wnd)->s32
    {
        var result: retval = 0
        var idx = col + (row * .numColumns)
        var r = row
        while r < .numRows
        {
            if .layout[idx] != child do
                break
            result += 1
            r += 1
            idx += .numColumns
        }

        return result
    }

    mtd computeContentSizes(columns: bool)->Array'f32
    {
        var result: retval
        let count = columns ? .numColumns : .numRows
        for count do
            result.add(0)

        var done: Array'(*Wnd)
        let client = .getClientRectPadding()
        for row in .numRows
        {
            for col in .numColumns
            {
                let idx = col + (row * .numColumns)
                let child = .layout[idx]
                if !child do
                    continue
                if done.contains(child) do
                    continue
                if !child.isVisibleState() do
                    continue
                done.add(child)

                let sh = .spanH(col, row, child)
                let sv = .spanV(col, row, child)
                let hint = child.measure({client.width, client.height})
                let margin = child.getLayoutMargin()
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

        var total = spacingTotal
        var weight = 0'f32
        for i in count
        {
            let size = .computeTrackSize(tracks[i], content[i])
            result.add(size)
            total += size
            if tracks[i].kind == GridTrackKind.Fraction or tracks[i].kind == GridTrackKind.Fill
            {
                var trackWeight = 1'f32
                if tracks[i].value > 0 do
                    trackWeight = tracks[i].value
                weight += trackWeight
            }
        }

        var extra = available - total
        if extra > 0 and weight > 0
        {
            for i in count
            {
                if tracks[i].kind != GridTrackKind.Fraction and tracks[i].kind != GridTrackKind.Fill do
                    continue

                let w = tracks[i].value > 0 ? tracks[i].value : 1
                let add = extra * w / weight
                result[i] = Math.min(result[i] + add, .trackMax(tracks[i]))
            }
        }
        elif extra < 0
        {
            var shrinkPool = 0'f32
            for i in count do
                shrinkPool += Math.max(result[i] - tracks[i].min, 0)

            if shrinkPool > 0
            {
                let shortage = -extra
                for i in count
                {
                    let shrink = Math.max(result[i] - tracks[i].min, 0)
                    result[i] -= shortage * shrink / shrinkPool
                    result[i] = Math.max(result[i], tracks[i].min)
                }
            }
        }

        return result
    }

    mtd trackOffset(sizes: [..] f32, idx: s32, spacing: f32)->f32
    {
        var result: retval
        for i in idx
        {
            result += sizes[i]
            result += spacing
        }

        return result
    }

    mtd trackSpanSize(sizes: [..] f32, idx, span: s32, spacing: f32)->f32
    {
        var result: retval
        for i in span
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
    // Create a layout control
    func create(parent: *Wnd, numColumns, numRows: s32, position: Math.Rectangle = {})->*GridLayoutCtrl
    {
        Debug.assert(numColumns > 0 and numRows > 0)

        let res = Wnd.create'GridLayoutCtrl(parent, position)
        res.numColumns = numColumns
        res.numRows    = numRows
        res.ensureStorage()

        return res
    }

    // Recompute layout of all childs
    mtd computeLayout()
    {
        if !.childs.count do
            return
        .ensureStorage()

        let client = .getClientRectPadding()
        let colContent = .computeContentSizes(true)
        let rowContent = .computeContentSizes(false)
        let colWidths = .computeTrackSizes(.colTracks.toSlice(), colContent.toSlice(), client.width, .spacingHorz, .gridLayoutFlags.has(.AdaptColWidth))
        let rowHeights = .computeTrackSizes(.rowTracks.toSlice(), rowContent.toSlice(), client.height, .spacingVert, .gridLayoutFlags.has(.AdaptRowHeight))

        var done: Array'(*Wnd)
        var maxW, maxH = 0'f32
        for row in .numRows
        {
            for col in .numColumns
            {
                let idx = col + (row * .numColumns)
                let child = .layout[idx]
                if !child do
                    continue
                if done.contains(child) do
                    continue
                if !child.isVisibleState() do
                    continue

                done.add(child)
                let sh = .spanH(col, row, child)
                let sv = .spanV(col, row, child)

                var rect = Math.Rectangle{
                    client.x + .trackOffset(colWidths.toSlice(), col, .spacingHorz),
                    client.y + .trackOffset(rowHeights.toSlice(), row, .spacingVert),
                    .trackSpanSize(colWidths.toSlice(), col, sh, .spacingHorz),
                    .trackSpanSize(rowHeights.toSlice(), row, sv, .spacingVert)
                }

                rect.applyPadding(child.getLayoutMargin())
                child.arrange(rect)
                maxW = Math.max(maxW, rect.right() + .padding.z)
                maxH = Math.max(maxH, rect.bottom() + .padding.w)
            }
        }

        if .gridLayoutFlags.has(.AdaptSizeToContent)
        {
            .position.width = maxW
            .position.height = maxH
            .preferredSize = {maxW, maxH}
        }
    }

    // Set size, in pixel, of a given column
    mtd setColSize(col: s32, size: f32)
    {
        .ensureStorage()
        Debug.assert(col >= 0 and col < .numColumns)
        .colSizes[col] = size
        .setColTrack(col, GridTrackKind.Fixed, size)
    }

    // Set size, in pixel, of a given row
    mtd setRowSize(row: s32, size: f32)
    {
        .ensureStorage()
        Debug.assert(row >= 0 and row < .numRows)
        .rowSizes[row] = size
        .setRowTrack(row, GridTrackKind.Fixed, size)
    }

    mtd setColTrack(col: s32, kind: GridTrackKind, value: f32 = 1, min: f32 = 0, max: f32 = 0)
    {
        .ensureStorage()
        Debug.assert(col >= 0 and col < .numColumns)
        .colTracks[col] = {kind: kind, value: value, min: min, max: max}
    }

    mtd setRowTrack(row: s32, kind: GridTrackKind, value: f32 = 1, min: f32 = 0, max: f32 = 0)
    {
        .ensureStorage()
        Debug.assert(row >= 0 and row < .numRows)
        .rowTracks[row] = {kind: kind, value: value, min: min, max: max}
    }

    // Set the wnd associated with the given 'col' and 'row'.
    // Window can cover multiple columns and rows.
    mtd setColRowChild(child: *Wnd, col, row: s32, spanH, spanV: s32 = 1)
    {
        .ensureStorage()
        Debug.assert(child.parent == me)
        Debug.assert(col + spanH <= .numColumns and row + spanV <= .numRows)
        Debug.assert(spanH and spanV)

        for i in spanH
        {
            var x = col + (row * .numColumns)
            x += i
            for j in spanV
            {
                let x1 = x + (j * .numColumns)
                .layout[x1] = child
            }
        }
    }
}
