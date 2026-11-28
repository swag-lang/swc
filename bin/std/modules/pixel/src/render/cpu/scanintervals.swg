using Core, Core.Math

internal impl ScanScratch
{
    mtd startIntervalRows(height: s32)->[..] Array!{ScanInterval}
    {
        let count = cast(u64, height) * VerticalSamples
        .intervalRows.growResize(count)
        let rows = .intervalRows.toSlice()[until count]
        for &row in rows
        {
            row.clear()
        }

        return rows
    }

    mtd resolveIntervals(rows: [..] Array!{ScanInterval}, row, width: s32)->{values: [*] f32, first, end: u64}
    {
        .coverage.growResize(cast(u64, width))
        let coverage = .coverage.storage()
        let start    = cast(u64, row) * VerticalSamples
        let samples  = rows[start until start + VerticalSamples]
        var low      = cast(f32, width)
        var high: f32
        for &sample in samples where sample.count
        {
            var ordered   = true
            let intervals = sample.storage()
            var previous: f32
            for index in sample.count
            {
                let item = intervals[index]
                ordered  = ordered and previous <= item.left
                previous = item.left
                high     = Math.max(high, item.right)
            }

            if not ordered
            {
                sample.sort(func||(lhs, rhs) => lhs.left <=> rhs.left)
            }

            low = Math.min(low, sample[0].left)
        }

        let first = cast(u64, Math.floor(low))
        let end   = cast(u64, Math.ceil(high))
        if first >= end
        {
            return {coverage, 0, 0}
        }

        Memory.clear(coverage + first, (end - first) * #sizeof(f32))
        for &sample in samples where sample.count
        {
            paintIntervals(coverage, sample.toSlice())
        }

        return {coverage, first, end}
    }

    #[Swag.Inline]
    func paintIntervals(coverage: [*] f32, intervals: const [..] ScanInterval)
    {
        var covered = intervals[0]
        for interval in intervals[1 until intervals.count]
        {
            if interval.left > covered.right
            {
                addCoverageSpan(coverage, covered.left, covered.right)
                covered = interval
            }
            else
            {
                covered.right = Math.max(covered.right, interval.right)
            }
        }

        addCoverageSpan(coverage, covered.left, covered.right)
    }
}

private struct IntervalEdge
{
    point:        u64
    end:          s32
    x, y, dx, dy: f64
}

// Both chains of a vertically monotone stroke fragment cover the same sample rows.
// Pair their crossings as they are generated, so the winding resolver sees only intervals.
internal func addStrokeIntervals(rows: [..] Array!{ScanInterval}, source: const [..] Vector2, transform: const *Transform2, origin: Vector2, forwardRight: bool, firstRow: s32, minX, maxX: f32)->bool
{
    const Capacity = 16
    if source.count < 3 or source.count > Capacity
    {
        return false
    }

    var points:      [Capacity] Vector2
    var samples:     [Capacity] s32
    let start = firstRow * VerticalSamples
    let end   = cast(s32, rows.count)
    var low   = end
    var high  = start
    var top, bottom: u64
    for p, index in source
    {
        let point = transform.transformPoint(p) - origin
        if not point.isFinite()
        {
            return false
        }

        let row = cast(s32, Math.clamp(Math.ceil(point.y * VerticalSamples - 0.5), cast(f32, start), cast(f32, end)))
        points[index]  = point
        samples[index] = row
        if row < low
        {
            low = row
            top = index
        }

        if row > high
        {
            high   = row
            bottom = index
        }
    }

    if low >= high
    {
        return true
    }

    let count      = source.count
    var previous   = top
    var increasing = true
    for count
    {
        let next = previous + 1 == count ? 0_u64 : previous + 1
        if previous == bottom
        {
            increasing = false
        }

        if increasing ? samples[next] < samples[previous] : samples[next] > samples[previous]
        {
            return false
        }

        previous = next
    }

    var cursor = low
    var edges  = [IntervalEdge{point: top, end: low}, IntervalEdge{point: top, end: low}]
    while cursor < high
    {
        for &edge, side in edges
        {
            while edge.end <= cursor
            {
                let from = edge.point
                let next = side == 0 ? (from + 1 == count ? 0_u64 : from + 1) : (from == 0 ? count - 1 : from - 1)
                edge.point = next
                edge.end   = samples[next]
                if edge.end > cursor
                {
                    let a = points[from]
                    let b = points[next]
                    edge.x  = cast(f64, a.x)
                    edge.y  = cast(f64, a.y)
                    edge.dx = cast(f64, b.x) - edge.x
                    edge.dy = cast(f64, b.y) - edge.y
                }
            }
        }

        let stop  = Math.min(edges[0].end, edges[1].end)
        let right = edges[forwardRight ? 0 : 1]
        let left  = edges[forwardRight ? 1 : 0]
        for row in cursor until stop
        {
            let y = (cast(f64, row) + 0.5) / VerticalSamples
            let a = Math.clamp(cast(f32, left.x + left.dx * ((y - left.y) / left.dy)), minX, maxX)
            let b = Math.clamp(cast(f32, right.x + right.dx * ((y - right.y) / right.dy)), minX, maxX)
            if b < a
            {
                return false
            }

            if a < b
            {
                let list = &rows[row]
                if list.count
                {
                    let previous = list.storage() + list.count - 1
                    if a <= previous.right and b >= previous.left
                    {
                        previous.left  = Math.min(previous.left, a)
                        previous.right = Math.max(previous.right, b)
                        continue
                    }
                }

                list.add({a, b})
            }
        }

        cursor = stop
    }

    return true
}
