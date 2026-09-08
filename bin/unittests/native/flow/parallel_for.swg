#global private

// Empty and single-iteration ranges must not start workers, even on their first invocation.
#test
{
    let scheduler = Swag.schedulerInstance()
    let started   = scheduler.started.load()
    var total     = 0'u64
    parallel for |&total| index in 0 do
        total += index + 1
    parallel for |&total| index in 41 until 42 do
        total += index + 1
    Swag.assert(total == 42)
    Swag.assert(scheduler.started.load() == started)
}

// Reuse one loop body with different bounds, captures and costs. Scheduling history is only
// a hint: it must not retain a capture or change the set of completed iterations.
func fillProfiledRange(values: [..] u64, begin, count, rounds: u64)
{
    parallel for |values, begin, rounds| index in begin until begin + count
    {
        var value = index & 0xFFFF
        for round in rounds do
            value = (value * 33 + round) & 0xFFFF
        values[index - begin] += value + 1
    }
}

#test
{
    let counts: [6] u64 = [0, 1, 3, 257, 2048, 17]
    let costs:  [3] u64 = [0, 200, 0]
    for cost in costs
    {
        for count in counts
        {
            var values: [2048] u64
            let begin = 0xFFFF_FFFF_FFFF_0000'u64
            for repeat in 3 do
                fillProfiledRange(values, begin, count, cost)
            for index in count
            {
                var expected = (begin + index) & 0xFFFF
                for round in cost do
                    expected = (expected * 33 + round) & 0xFFFF
                Swag.assert(values[index] == (expected + 1) * 3)
            }
            for index in count until 2048 do
                Swag.assert(values[index] == 0)
        }
    }
}

// Several callers update the same loop's hint while its borrowed destinations stay disjoint.
#test
{
    var grid: [8][257] u64
    {
        var group: Swag.TaskGroup
        for row in 8
        {
            group.spawn(func|&grid, row|()
            {
                for repeat in 64 do
                    fillProfiledRange(grid[row], 100, 257, row % 3)
            })
        }
    }
    for row in 8
    {
        for index in 257
        {
            var expected = 100'u64 + index
            for round in row % 3 do
                expected = (expected * 33 + round) & 0xFFFF
            Swag.assert(grid[row][index] == (expected + 1) * 64)
        }
    }
}

// A native run has a real worker pool, so these cover what compile-time execution cannot: every
// index is still visited exactly once when several threads share the range.
#test
{
    var seen: [256] Swag.AtomicValue'u32

    parallel for |&seen| index in 256 do
        seen[index].add(1)

    for index in 256 do
        Swag.assert(seen[index].load() == 1)
}

#test
{
    var total: Swag.AtomicValue'u64

    parallel for |&total| index in 1000 do
        total.add(index)

    Swag.assert(total.load() == 499_500)
}

// Partition bounds are absolute indices of the written range.
#test
{
    var lowest:  Swag.AtomicValue'u64
    var highest: Swag.AtomicValue'u64
    lowest.store(Swag.U64.Max)

    parallel for |&lowest, &highest| index in 100 until 200
    {
        var seen = lowest.load()
        while index < seen and lowest.compareExchange(seen, index) != seen do
            seen = lowest.load()

        var top = highest.load()
        while index > top and highest.compareExchange(top, index) != top do
            top = highest.load()
    }

    Swag.assert(lowest.load() == 100)
    Swag.assert(highest.load() == 199)
}

// A nested statement runs its own partitioning inside a partition already running.
#test
{
    var grid: [64] Swag.AtomicValue'u32

    parallel for |&grid| row in 64
    {
        parallel for |&grid, row| column in 16 do
            grid[row].add(1)
    }

    for row in 64 do
        Swag.assert(grid[row].load() == 16)
}

// Repeated statements reuse the pool without losing an index.
#test
{
    var total: Swag.AtomicValue'u64

    for round in 20
    {
        parallel for |&total| index in 50 do
            total.add(1)
    }

    Swag.assert(total.load() == 1000)
}
