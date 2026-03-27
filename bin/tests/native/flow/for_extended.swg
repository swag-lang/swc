#global fileprivate

// For with 0 iterations
#test
{
    var count = 0
    for 0
    {
        count += 1
    }
    @assert(count == 0)
}

// For with index and 0 iterations
#test
{
    var count = 0
    for i in 0
    {
        count += 1
    }
    @assert(count == 0)
}

// For with 1 iteration
#test
{
    var count = 0
    for 1
    {
        count += 1
    }
    @assert(count == 1)
}

// For breaking immediately on first iteration
#test
{
    var count = 0
    for i in 10
    {
        count += 1
        break
    }
    @assert(count == 1)
}

// For with continue skipping all processing
#test
{
    var sum = 0
    for i in 5
    {
        continue
        sum += 1 // unreachable
    }
    @assert(sum == 0)
}

// For with where clause filtering everything
#test
{
    var count = 0
    for i in 10 where i > 100
    {
        count += 1
    }
    @assert(count == 0)
}

// For with where clause matching everything
#test
{
    var count = 0
    for i in 5 where i < 100
    {
        count += 1
    }
    @assert(count == 5)
}

// Reverse for with 0 iterations
#test
{
    var count = 0
    for #reverse 0
    {
        count += 1
    }
    @assert(count == 0)
}

// Reverse for with 1 iteration
#test
{
    var count = 0
    for #reverse 1
    {
        count += 1
    }
    @assert(count == 1)
}

// Nested for with inner break, outer continues
#test
{
    var outerCount = 0
    var innerTotal = 0
    for i in 4
    {
        outerCount += 1
        for j in 10
        {
            innerTotal += 1
            if j == 2 do
                break
        }
    }
    @assert(outerCount == 4)
    @assert(innerTotal == 12) // 4 * 3 iterations each
}

// For on single-element array
#test
{
    var arr: [1]s32 = [42]
    var count = 0
    var sum = 0
    for v in arr
    {
        count += 1
        sum += cast(s32) v
    }
    @assert(count == 1)
}

// For with early return
func forEarlyReturn()->s32
{
    for i in 10
    {
        if i == 3 do
            return cast(s32) i
    }
    return -1
}

#test
{
    @assert(forEarlyReturn() == 3)
}

// Triple nested for
#test
{
    var count = 0
    for 3
    {
        for 3
        {
            for 3
            {
                count += 1
            }
        }
    }
    @assert(count == 27)
}

// For with do single statement form and break
#test
{
    var count = 0
    for i in 5
    {
        if i == 3 do
            break
        count += 1
    }
    @assert(count == 3)
}

// Range to with same start and end (single element)
#test
{
    var count = 0
    var val = -1
    for i in 5 to 5
    {
        val = cast(s32) i
        count += 1
    }
    @assert(count == 1)
    @assert(val == 5)
}

// Range until with adjacent values (1 iteration)
#test
{
    var count = 0
    var val = -1
    for i in 5 until 6
    {
        val = cast(s32) i
        count += 1
    }
    @assert(count == 1)
    @assert(val == 5)
}

// For with multiple continues at different points
#test
{
    var sum = 0
    for i in 20
    {
        if i % 2 == 0 do
            continue
        if i % 5 == 0 do
            continue
        sum += cast(s32) i
    }
    // odd numbers not divisible by 5: 1,3,7,9,11,13,17,19 = 80
    @assert(sum == 80)
}

// For loop variable used after loop
#test
{
    var lastI = -1
    for i in 5
    {
        lastI = cast(s32) i
    }
    @assert(lastI == 4)
}

// Nested for with where clauses
#test
{
    var count = 0
    for i in 10 where i % 2 == 0
    {
        for j in 10 where j % 3 == 0
        {
            count += 1
        }
    }
    // i: 0,2,4,6,8 (5 values), j: 0,3,6,9 (4 values) = 20
    @assert(count == 20)
}
