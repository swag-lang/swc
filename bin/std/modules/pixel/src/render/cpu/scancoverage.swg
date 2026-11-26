using Core, Core.Math

internal const VerticalSamples = 4

// A crossing of a horizontal sample line and one directed contour edge.
internal struct Crossing
{
    x:       f32
    winding: s32
}

internal struct ScanScratch
{
    rows:     Array'Array'Crossing
    coverage: Array'f32
    sorted:   Array'Crossing
}

internal impl ScanScratch
{
    // Reuses the crossing buffers of the preceding shape or tile.
    mtd startRows(height: s32)->[..] Array'Crossing
    {
        let count = cast(u64, height) * VerticalSamples
        if .rows.count < count do
            .rows.resize(count)
        let crossings = .rows.toSlice()[0 until count]
        for &line in crossings do
            line.clear()
        return crossings
    }

    // Integrates horizontal coverage at four vertical sample positions per device row.
    mtd resolveRow(crossings: [..] Array'Crossing, row, width: s32, evenOdd, fullRow: bool)->{values: [*] f32, first, end: u64}
    {
        func sortLine(line: *Array'Crossing, scratch: *Array'Crossing)
        {
            #[Swag.Inline]
            func insertWithGap(points: [*] Crossing, count, gap: u64)
            {
                for index in gap until count
                {
                    let crossing = points[index]
                    var target   = index
                    while target >= gap and points[target - gap].x > crossing.x
                    {
                        points[target] = points[target - gap]
                        target         -= gap
                    }

                    points[target] = crossing
                }
            }

            if line.count < 128
            {
                let points = line.storage()

                // A few coarse passes move out-of-order crossings before the final insertion pass.
                if line.count > 8
                {
                    for gap in [23'u64, 10, 4] do
                        insertWithGap(points, line.count, gap)
                }

                insertWithGap(points, line.count, 1)
                return
            }

            // Nonnegative f32 values have the same order as their unsigned bits.
            // Radix sorting long lines avoids repeated comparison calls at each sample.
            scratch.resize(line.count)
            var source = line.storage()
            var target = scratch.storage()
            for digit in 4
            {
                let shift = digit * 8
                var offsets: [256] u64
                for index in line.count
                {
                    let key = cast #bit(u32, source[index].x) & 0x7FFF_FFFF
                    offsets[(key >> shift) & 0xFF] += 1
                }

                var total = 0'u64
                for &offset in offsets
                {
                    let count = offset[]
                    offset[] = total
                    total    += count
                }

                for index in line.count
                {
                    let crossing = source[index]
                    let key      = cast #bit(u32, crossing.x) & 0x7FFF_FFFF
                    let bucket   = (key >> shift) & 0xFF
                    target[offsets[bucket]] = crossing
                    offsets[bucket]         += 1
                }

                swap(&source, &target)
            }
        }

        if .coverage.count < cast(u64, width) do
            .coverage.resize(cast(u64, width))
        let coverage = .coverage.storage()
        let rowStart = cast(u64, row) * VerticalSamples
        let samples  = crossings[rowStart until rowStart + VerticalSamples]

        var low  = cast(f32, width)
        var high = 0.0'f32
        for &sample in samples where sample.count > 1
        {
            sortLine(sample, &.sorted)
            low  = Math.min(low, sample[0].x)
            high = Math.max(high, sample[sample.count - 1].x)
        }

        // For a sloped edge most of the bounding-box row has no crossings.
        // A texture mask still needs initialized zeros outside the covered interval.
        let first = fullRow ? 0'u64 : cast(u64, Math.floor(low))
        let end   = fullRow ? cast(u64, width) : cast(u64, Math.ceil(high))
        if first >= end do
            return {coverage, 0, 0}
        Memory.clear(coverage + first, (end - first) * #sizeof(f32))
        for &line in samples
        {
            var winding:  s32
            var previous: f32
            for crossing in line
            {
                let x = crossing.x
                if x > previous and (evenOdd ? (winding & 1) != 0 : winding != 0)
                {
                    let start = cast(u64, Math.floor(previous))
                    let last  = cast(u64, Math.ceil(x)) - 1
                    if start == last
                    {
                        coverage[start] += x - previous
                    }
                    else
                    {
                        coverage[start] += cast(f32, start + 1) - previous
                        for column in start + 1 until last do
                            coverage[column] += 1
                        coverage[last] += x - cast(f32, last)
                    }
                }

                winding  += crossing.winding
                previous = x
            }
        }

        return {coverage, first, end}
    }
}

internal func addScanContour(crossings: [..] Array'Crossing, points: const [..] Vector2, transform: const *Transform2, density: f32, origin: Vector2, uniform: bool, width: f32)
{
    #[Swag.Inline]
    func project(point: Vector2, transform: const *Transform2, density: f32, origin: Vector2, uniform: bool)->Vector2
    {
        if uniform do
            return point * transform.m11 - origin
        return transform.transformPoint(point) * density - origin
    }

    #[Swag.Inline]
    func sampleRow(point: Vector2, limit: f32)->s64
    {
        if not point.isFinite() do
            return -1
        return cast(s64, Math.clamp(Math.ceil(point.y * VerticalSamples - 0.5), 0.0, limit))
    }

    func addEdge(rows: [..] Array'Crossing, a, b: Vector2, aRow, bRow: s64, width: f32)
    {
        let forward = aRow < bRow
        let top     = forward ? a : b
        let bottom  = forward ? b : a
        let start   = cast(u64, forward ? aRow : bRow)
        let end     = cast(u64, forward ? bRow : aRow)
        let winding = forward ? 1 : -1
        if top.x == bottom.x
        {
            let crossing = Crossing{Math.clamp(top.x, 0, width), winding}
            for row in start until end do
                rows[row].add(crossing)
            return
        }

        let topX = cast(f64, top.x)
        let topY = cast(f64, top.y)
        let dx   = cast(f64, bottom.x) - topX
        let dy   = cast(f64, bottom.y) - topY
        for row in start until end
        {
            let y       = (cast(f32, row) + 0.5) / VerticalSamples
            let portion = (cast(f64, y) - topY) / dy
            let x       = cast(f32, topX + dx * portion)

            // Crossings outside the tile can share its boundary: between them
            // there is no span of visible pixels, only a change of winding.
            rows[row].add(Crossing{Math.clamp(x, 0, width), winding})
        }
    }

    let limit = cast(f32, crossings.count)
    if points.count < 2 do
        return

    // Adjacent edges share the projected vertex and its sample row.
    var previous    = project(points[points.count - 1], transform, density, origin, uniform)
    var previousRow = sampleRow(previous, limit)
    for point in points
    {
        let next = project(point, transform, density, origin, uniform)
        let row  = sampleRow(next, limit)
        if previousRow >= 0 and row >= 0 and previousRow != row do
            addEdge(crossings, previous, next, previousRow, row, width)
        previous    = next
        previousRow = row
    }
}
