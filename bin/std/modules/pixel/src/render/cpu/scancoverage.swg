using Core, Core.Math

internal const VerticalSamples = 4

// A crossing of a horizontal sample line and one directed contour edge.
internal struct Crossing
{
    x:       f32
    winding: s32
}

internal struct ScanSample
{
    y:         f64
    crossings: Array'Crossing
}

internal struct ScanScratch
{
    rows:     Array'ScanSample
    coverage: Array'f32
    order:    Array'u32
    reordered: Array'Crossing
    keys, sorted: Array'u64
}

internal impl ScanScratch
{
    // Reuses the crossing buffers of the preceding shape or tile.
    mtd startRows(height: s32)->[..] ScanSample
    {
        .order.clear()
        let count = cast(u64, height) * VerticalSamples
        if .rows.count < count
        {
            let first = .rows.count
            .rows.resize(count)

            // The sample grid is local to the tile, so its ordinates survive clearing the rows.
            for row in first until count do
                .rows[row].y = cast(f64, (cast(f32, row) + 0.5) / VerticalSamples)
        }

        let crossings = .rows.toSlice()[0 until count]
        for &line in crossings do
            line.crossings.clear()
        return crossings
    }

    // The same set of edges usually crosses multiple nearby samples. Reusing the
    // previous permutation often leaves only local exchanges. The repair has a
    // fixed budget, so a different set of edges falls back to a full sort.
    mtd reorderLine(line: *Array'Crossing)->bool
    {
        let count = line.count
        if .order.count != count do
            return false
        .reordered.growResize(count)
        let old = line.storage()
        let target = .reordered.storage()
        let order = .order.storage()
        var exchanges = 16 + count / 8
        for index in count
        {
            let original = order[index]
            let crossing = old[original]
            var slot = index
            while slot and target[slot - 1].x > crossing.x
            {
                if not exchanges do
                    return false
                exchanges -= 1
                target[slot] = target[slot - 1]
                order[slot]  = order[slot - 1]
                slot -= 1
            }
            target[slot] = crossing
            order[slot]  = original
        }
        Memory.copy(old, target, count * #sizeof(Crossing))
        return true
    }

    mtd sortLine(line: *Array'Crossing)
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

        if .reorderLine(line) do
            return

        // Sort the original indices by the nonnegative float's unsigned bits.
        // The indices themselves are payload and do not take part in the sort.
        .keys.growResize(line.count)
        .sorted.growResize(line.count)
        .order.resize(line.count)
        .reordered.growResize(line.count)
        var source = .keys.storage()
        var target = .sorted.storage()
        let crossings = line.storage()
        for index in line.count
        {
            let key = cast #bit(u32, crossings[index].x) & 0x7FFF_FFFF
            source[index] = (cast(u64, key) << 32) | index
        }

        for digit in 4
        {
            let shift = 32 + digit * 8
            var offsets: [256] u64
            for index in line.count do
                offsets[(source[index] >> shift) & 0xFF] += 1
            var total = 0'u64
            for &offset in offsets
            {
                let count = offset[]
                offset[] = total
                total    += count
            }

            for index in line.count
            {
                let key = source[index]
                let bucket = (key >> shift) & 0xFF
                target[offsets[bucket]] = key
                offsets[bucket] += 1
            }
            swap(&source, &target)
        }

        let ordered = .reordered.storage()
        for index in line.count
        {
            let original = cast(u32, source[index] & Swag.U32.Max)
            .order[index] = original
            ordered[index] = crossings[original]
        }
        Memory.copy(crossings, ordered, line.count * #sizeof(Crossing))
    }

    // Integrates horizontal coverage at four vertical sample positions per device row.
    mtd resolveRow(crossings: [..] ScanSample, row, width: s32, evenOdd, fullRow: bool, sortedRows = false)->{values: [*] f32, first, end: u64}
    {
        if .coverage.count < cast(u64, width) do
            .coverage.resize(cast(u64, width))
        let coverage = .coverage.storage()
        let rowStart = cast(u64, row) * VerticalSamples
        let samples  = crossings[rowStart until rowStart + VerticalSamples]

        var low  = cast(f32, width)
        var high = 0.0'f32
        for &sample in samples where sample.crossings.count > 1
        {
            let line = &sample.crossings
            if not sortedRows do
                .sortLine(line)
            low  = Math.min(low, line[0].x)
            high = Math.max(high, line[line.count - 1].x)
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
            for crossing in line.crossings
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
                        var column = start + 1
                        let one    = Math.Simd.splat(1.0'f32)
                        while last - column >= 4
                        {
                            let pixels = coverage + column
                            Math.Simd.store(pixels, Math.Simd.load(pixels) + one)
                            column += 4
                        }

                        for tail in column until last do
                            coverage[tail] += 1
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

internal func addScanContour(crossings: [..] ScanSample, points: const [..] Vector2, transform: const *Transform2, density: f32, origin: Vector2, uniform: bool, width: f32, minimumX = 0.0'f32)
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

    func addEdge(rows: [..] ScanSample, a, b: Vector2, aRow, bRow: s64, minimumX, width: f32)
    {
        let forward = aRow < bRow
        let top     = forward ? a : b
        let bottom  = forward ? b : a
        let start   = cast(u64, forward ? aRow : bRow)
        let end     = cast(u64, forward ? bRow : aRow)
        let winding = forward ? 1 : -1
        if top.x == bottom.x
        {
            let crossing = Crossing{Math.clamp(top.x, minimumX, width), winding}
            for row in start until end do
                rows[row].crossings.add(crossing)
            return
        }

        let topX = cast(f64, top.x)
        let topY = cast(f64, top.y)
        let dx   = cast(f64, bottom.x) - topX
        let dy   = cast(f64, bottom.y) - topY
        for row in start until end
        {
            let sample  = &rows[row]
            let portion = (sample.y - topY) / dy
            let x       = cast(f32, topX + dx * portion)

            // Crossings outside the tile can share its boundary: between them
            // there is no span of visible pixels, only a change of winding.
            sample.crossings.add(Crossing{Math.clamp(x, minimumX, width), winding})
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
            addEdge(crossings, previous, next, previousRow, row, minimumX, width)
        previous    = next
        previousRow = row
    }
}
