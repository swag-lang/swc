#global private

// Compile-time execution runs every partition on the calling thread, which is the one-worker
// case the statement must already answer. The results are therefore the sequential ones.
#test
{
    var seen: [16] u32

    parallel for |&seen| index in 16 do
        seen[index] += 1

    for index in 16 do
        Swag.assert(seen[index] == 1)
}

#test
{
    var total = 0'u64

    parallel for |&total| index in 10 until 20 do
        total += index

    Swag.assert(total == 145)
}

// An inclusive range covers its upper bound.
#test
{
    var total = 0'u64

    parallel for |&total| index in 1 to 4 do
        total += index

    Swag.assert(total == 10)
}

// An empty range runs no iteration.
#test
{
    var ran = false

    parallel for |&ran| index in 0 do
        ran = true

    Swag.assert(!ran)

    parallel for |&ran| index in 5 until 5 do
        ran = true

    Swag.assert(!ran)
}

// The bounds take any integer expression, and the index is an index.
#test
{
    let count = 6's32
    var total = 0'u64

    parallel for |&total, count| index in count do
        total += index * cast(u64) count

    Swag.assert(total == 90)
}

// 'continue' skips one index of the partition.
#test
{
    var total = 0'u64

    parallel for |&total| index in 10
    {
        if index & 1 do
            continue
        total += index
    }

    Swag.assert(total == 20)
}

// A loop with no capture list captures nothing.
#test
{
    var visited = 0'u32
    let counter = &visited

    parallel for |counter| index in 4 do
        counter[] += 1

    Swag.assert(visited == 4)
}

// Nested statements keep their own index.
#test
{
    var grid: [4] u32

    parallel for |&grid| row in 4
    {
        parallel for |&grid, row| column in 3 do
            grid[row] += 1
    }

    for row in 4 do
        Swag.assert(grid[row] == 3)
}
