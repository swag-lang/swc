#global private

// More distinct bodies than the bounded runtime table can hold. Each specialization uses its
// own constant and destination, so identical-code folding cannot merge the loop entry points.
func(First: u64, Count: u64) fillManyProfiles(values: *[512][17] u64, width, begin: u64, rounds = 0'u64)
{
    #static if Count == 1
    {
        parallel for |values, begin, rounds| index in begin until begin + width
        {
            var value = First + (index - begin) + 1
            for round in rounds do
                value = (value * 33 + round) & 0xFFFF
            values[][First][index - begin] += value
        }
    }
    else
    {
        fillManyProfiles'(First, Count / 2)(values, width, begin, rounds)
        fillManyProfiles'(First + Count / 2, Count - Count / 2)(values, width, begin, rounds)
    }
}

// Uncached expensive work still uses its measured cost; cached bodies can carry older hints.
#test
{
    var values: [512][17] u64
    for repeat in 2 do
        fillManyProfiles'(0, 512)(&values, 3, 100, 32768)
    for leaf in 512
    {
        for index in 3
        {
            var expected = leaf + index + 1
            for round in 32768 do
                expected = (expected * 33 + round) & 0xFFFF
            Swag.assert(values[leaf][index] == expected * 2)
        }
        for index in 3 until 17 do
            Swag.assert(values[leaf][index] == 0)
    }
}

// Cache pressure must not lose the pilot iteration, replay it, or retain earlier captures.
#test
{
    Swag.setWorkerCount(4)
    let widths: [4] u64 = [0, 1, 3, 17]
    for width in widths
    {
        var values: [512][17] u64
        for repeat in 17 do
            fillManyProfiles'(0, 512)(&values, width, 0xFFFF_FFFF_FFFF_FFE0)
        for leaf in 512
        {
            for index in 17 do
                Swag.assert(values[leaf][index] == (index < width ? 17 * (leaf + index + 1) : 0))
        }
    }
}

// Concurrent callers share profile entries, but every borrowed destination stays disjoint.
#test
{
    var grids: [3][512][17] u64
    {
        var group: Swag.TaskGroup
        for lane in 3
        {
            group.spawn(func|&grids, lane|()
            {
                for repeat in 17 do
                    fillManyProfiles'(0, 512)(&grids[lane], 17, lane * 100)
            })
        }
    }
    for lane in 3
    {
        for leaf in 512
        {
            for index in 17 do
                Swag.assert(grids[lane][leaf][index] == 17 * (leaf + index + 1))
        }
    }
}
