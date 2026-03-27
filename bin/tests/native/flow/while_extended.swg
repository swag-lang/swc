#global fileprivate

// While with false condition - body never executes
#test
{
    var count = 0
    while false
    {
        count += 1
    }
    @assert(count == 0)
}

// While with break
#test
{
    var count = 0
    while true
    {
        count += 1
        if count == 5 do
            break
    }
    @assert(count == 5)
}

// While with continue
#test
{
    var sum = 0
    var i = 0
    while i < 10
    {
        i += 1
        if i % 2 == 0 do
            continue
        sum += i
    }
    @assert(sum == 25) // 1 + 3 + 5 + 7 + 9
}

// While with both break and continue
#test
{
    var sum = 0
    var i = 0
    while true
    {
        i += 1
        if i > 10 do
            break
        if i % 3 == 0 do
            continue
        sum += i
    }
    // 1 + 2 + 4 + 5 + 7 + 8 + 10 = 37
    @assert(sum == 37)
}

// While with complex boolean condition (AND)
#test
{
    var i = 0
    var j = 10
    var count = 0
    while i < 5 and j > 5
    {
        i += 1
        j -= 1
        count += 1
    }
    @assert(count == 5)
    @assert(i == 5)
    @assert(j == 5)
}

// While with complex boolean condition (OR)
#test
{
    var i = 0
    var done = false
    while i < 3 or !done
    {
        i += 1
        if i >= 5 do
            done = true
    }
    @assert(i == 5)
}

// While with early return from function
func whileEarlyReturn(limit: s32)->s32
{
    var i = 0
    while i < 100
    {
        i += 1
        if i == limit do
            return i
    }
    return -1
}

#test
{
    @assert(whileEarlyReturn(7) == 7)
    @assert(whileEarlyReturn(1) == 1)
}

// Nested while with outer break
#test
{
    var total = 0
    var i = 0
    while i < 5
    {
        var j = 0
        while j < 5
        {
            j += 1
            total += 1
            if j == 2 do
                break // only breaks inner
        }
        i += 1
    }
    @assert(total == 10) // 5 outer * 2 inner
}

// While modifying condition variable in complex way
#test
{
    var x = 1
    var steps = 0
    while x < 100
    {
        x *= 2
        steps += 1
    }
    @assert(x == 128)
    @assert(steps == 7)
}

// While with side effect in condition
var gSideEffectCount: s32 = 0
func sideEffectCheck(val: s32)->bool
{
    gSideEffectCount += 1
    return val < 3
}

#test
{
    gSideEffectCount = 0
    var i = 0
    while sideEffectCheck(i)
    {
        i += 1
    }
    @assert(i == 3)
    @assert(gSideEffectCount == 4) // checked 0,1,2,3 - last check returns false
}

// While single iteration
#test
{
    var count = 0
    var i = 0
    while i < 1
    {
        count += 1
        i += 1
    }
    @assert(count == 1)
}
