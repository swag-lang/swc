#global private

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
