using Core, Core.Math

// Each sample line holds sorted pairs of crossings for its surviving intervals.
internal struct ScanIntersection
{
    rows:   Array'ScanSample
    merged: Array'Crossing
}

internal impl ScanIntersection
{
    mtd startBand(count: u64)
    {
        if .rows.count < count do
            .rows.resize(count)
    }

    mtd intersect(scratch: *ScanScratch, crossings: [..] ScanSample, evenOdd, first: bool)->bool
    {
        func appendInterval(row: *Array'Crossing, left, right: f32)
        {
            // Adjacent spans are one interval, even when the input winding changed between them.
            if row.count and row[row.count - 1].x == left
            {
                row[row.count - 1].x = right
                return
            }

            row.add(Crossing{left, 1})
            row.add(Crossing{right, -1})
        }

        var hasCoverage: bool
        for &sample, index in crossings
        {
            let line     = &sample.crossings
            let existing = &.rows[index].crossings
            if line.count < 2
            {
                existing.clear()
                continue
            }

            if not first and existing.isEmpty() do
                continue

            scratch.sortLine(line)
            .merged.clear()
            var winding:  s32
            var previous: f32
            var cursor:   u64
            for crossing in line
            {
                let right = crossing.x
                if right > previous and (evenOdd ? (winding & 1) != 0 : winding != 0)
                {
                    if first
                    {
                        appendInterval(&.merged, previous, right)
                    }
                    else
                    {
                        while cursor < existing.count and existing[cursor].x < right
                        {
                            let end  = existing[cursor + 1].x
                            let left = Math.max(previous, existing[cursor].x)
                            if left < end do
                                appendInterval(&.merged, left, Math.min(end, right))
                            if end > right do
                                break
                            cursor += 2
                        }
                    }
                }

                winding  += crossing.winding
                previous = right
            }

            swap(existing, &.merged)
            hasCoverage = hasCoverage or existing.count != 0
        }

        return hasCoverage
    }
}
