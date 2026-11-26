using Core, Core.Math

// An edge adds signed vertical coverage to every cell on its right. The
// part of the same edge inside this cell contributes its trapezoid area.
internal struct AreaCell
{
    column:  s32
    advance: f64
    area:    f64
}

internal struct AreaScratch
{
    rows:     Array'(Array'AreaCell)
    coverage: Array'f32
}

internal impl AreaScratch
{
    mtd rasterize(points: const [..] Vector2, width, height: s32, firstRow = 0's32)
    {
        .rows.growResize(cast(u64, height))
        for i in firstRow until height do
            .rows[i].clear()
        .coverage.growResize(cast(u64, width))

        var previous = points[points.count - 1]
        for next in points
        {
            if previous.y != next.y
            {
                let low    = previous.y < next.y ? previous : next
                let high   = previous.y < next.y ? next : previous
                let sign   = previous.y < next.y ? 1.0'f64 : -1.0'f64
                let top    = Math.max(cast(f64, firstRow), cast(f64, low.y))
                let bottom = Math.min(cast(f64, height), cast(f64, high.y))
                if top < bottom
                {
                    let ax    = cast(f64, low.x)
                    let ay    = cast(f64, low.y)
                    let slope = (cast(f64, high.x) - ax) / (cast(f64, high.y) - ay)
                    for y in cast(s32, Math.floor(top)) until cast(s32, Math.ceil(bottom))
                    {
                        let first = Math.max(top, cast(f64, y))
                        let end   = Math.min(bottom, cast(f64, y + 1))
                        let x0    = ax + slope * (first - ay)
                        let x1    = ax + slope * (end - ay)
                        accumulateArea(&.rows[y], Math.min(x0, x1), Math.max(x0, x1), (end - first) * sign, width)
                    }
                }
            }

            previous = next
        }
    }

    // Split the clipped edge segment at pixel boundaries. Its signed
    // vertical length is distributed in proportion to horizontal distance.
    func accumulateArea(cells: *Array'AreaCell, low, high, delta: f64, width: s32)
    {
        if low >= cast(f64, width) do
            return
        if high <= 0
        {
            cells.add({0, delta, delta})
            return
        }

        if low == high
        {
            let column = cast(s32, Math.floor(low))
            cells.add({column, delta, delta * (cast(f64, column + 1) - low)})
            return
        }

        let slope = delta / (high - low)
        if low < 0
        {
            let before = -low * slope
            cells.add({0, before, before})
        }

        let first = cast(s32, Math.floor(Math.max(0.0'f64, low)))
        let end   = cast(s32, Math.ceil(Math.min(cast(f64, width), high)))
        for column in first until end
        {
            let left    = Math.max(low, cast(f64, column))
            let right   = Math.min(high, cast(f64, column + 1))
            let advance = (right - left) * slope
            let area    = advance * (cast(f64, column + 1) - (left + right) * 0.5)
            cells.add({column, advance, area})
        }
    }

    mtd resolve(row: s32, width: s32)->{values: [*] f32, first, end: u64}
    {
        let values = .coverage.storage()
        let cells  = &.rows[row]
        if not cells.count do
            return {values, 0, 0}

        let entries = cells.storage()
        if cells.count > 32 do
            cells.sort(func||(lhs, rhs) => lhs.column <=> rhs.column)
        else
        {
            for index in 1 until cells.count
            {
                let entry = entries[index]
                var slot  = index
                while slot and entries[slot - 1].column > entry.column
                {
                    entries[slot] = entries[slot - 1]
                    slot -= 1
                }
                entries[slot] = entry
            }
        }

        let first = entries[0].column
        var current = first
        var position: u64
        var running: f64
        while position < cells.count
        {
            let column = entries[position].column
            let fill = cast(f32, Math.min(Math.abs(running), 1.0'f64) * VerticalSamples)
            let packed = Math.Simd.splat(fill)
            while column - current >= 4
            {
                Math.Simd.store(values + current, packed)
                current += 4
            }
            for x in current until column do
                values[x] = fill

            var area, advance: f64
            while position < cells.count and entries[position].column == column
            {
                area    += entries[position].area
                advance += entries[position].advance
                position += 1
            }

            values[column] = cast(f32, Math.min(Math.abs(running + area), 1.0'f64) * VerticalSamples)
            running += advance
            current = column + 1
        }

        if Math.abs(running) > 0.00001
        {
            let fill = cast(f32, Math.min(Math.abs(running), 1.0'f64) * VerticalSamples)
            for x in current until width do
                values[x] = fill
            current = width
        }

        return {values, cast(u64, first), cast(u64, current)}
    }
}

// The winding magnitude of a simple contour is at most one, so the
// absolute signed area gives its true coverage under either fill rule.
internal func isSimpleAreaContour(points: const [..] Vector2)->bool
{
    func turn(a, b, c: Vector2)->f64
    {
        return (cast(f64, b.x) - a.x) * (cast(f64, c.y) - a.y) -
               (cast(f64, b.y) - a.y) * (cast(f64, c.x) - a.x)
    }

    for i in points.count
    {
        let a = points[i]
        let b = points[(i + 1) % points.count]
        if not a.isFinite() or Math.abs(a.x) > 16384 or Math.abs(a.y) > 16384 or a == b do
            return false
        for j in i + 2 until points.count
        {
            if i == 0 and j + 1 == points.count do
                break
            let c = points[j]
            let d = points[(j + 1) % points.count]
            if Math.max(a.x, b.x) < Math.min(c.x, d.x) or Math.max(c.x, d.x) < Math.min(a.x, b.x) or
               Math.max(a.y, b.y) < Math.min(c.y, d.y) or Math.max(c.y, d.y) < Math.min(a.y, b.y) do
                continue
            let t0 = turn(a, b, c)
            let t1 = turn(a, b, d)
            let t2 = turn(c, d, a)
            let t3 = turn(c, d, b)
            if t0 * t1 <= 0 and t2 * t3 <= 0 do
                return false
        }
    }

    return true
}
