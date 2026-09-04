#global private

// Closure created in a loop captures by value correctly
#test
{
    var closures: [5] #null func||()->s32 = cast(#null func||()->s32) null

    for i in 5
    {
        let idx = cast(s32) i
        closures[i] = func|idx|()->s32 { return idx }
    }

    Swag.assert(closures[0]!() == 0)
    Swag.assert(closures[1]!() == 1)
    Swag.assert(closures[2]!() == 2)
    Swag.assert(closures[3]!() == 3)
    Swag.assert(closures[4]!() == 4)
}

// Closure captures computed value in loop
#test
{
    var closures: [4] #null func||()->s32 = cast(#null func||()->s32) null

    for i in 4
    {
        let squared = cast(s32) (i * i)
        closures[i] = func|squared|()->s32 { return squared }
    }

    Swag.assert(closures[0]!() == 0)
    Swag.assert(closures[1]!() == 1)
    Swag.assert(closures[2]!() == 4)
    Swag.assert(closures[3]!() == 9)
}

// Multiple closures from same iteration capture different values
#test
{
    var adders:   [3] #null func||()->s32 = cast(#null func||()->s32) null
    var doublers: [3] #null func||()->s32 = cast(#null func||()->s32) null

    for i in 3
    {
        let val = cast(s32) i
        adders[i]   = func|val|()->s32 { return val + 10 }
        doublers[i] = func|val|()->s32 { return val * 2 }
    }

    Swag.assert(adders[0]!() == 10)
    Swag.assert(adders[1]!() == 11)
    Swag.assert(adders[2]!() == 12)
    Swag.assert(doublers[0]!() == 0)
    Swag.assert(doublers[1]!() == 2)
    Swag.assert(doublers[2]!() == 4)
}

// Closure in while loop
#test
{
    var closures: [3] #null func||()->s32 = cast(#null func||()->s32) null
    var i = 0
    while i < 3
    {
        let captured = i
        closures[i] = func|captured|()->s32 { return captured }
        i           += 1
    }

    Swag.assert(closures[0]!() == 0)
    Swag.assert(closures[1]!() == 1)
    Swag.assert(closures[2]!() == 2)
}

// Closure capturing accumulator pattern
func makeAccumulator(start: s32)->func||(s32)->s32
{
    var total = start
    return func|var total|(delta: s32)->s32
    {
        total += delta
        return total
    }
}

#test
{
    let acc = makeAccumulator(0)
    Swag.assert(acc(5) == 5)
    Swag.assert(acc(3) == 8)
    Swag.assert(acc(2) == 10)
}

// Two independent closures from same function (separate captures)
#test
{
    let a = makeAccumulator(10)
    let b = makeAccumulator(100)
    Swag.assert(a(1) == 11)
    Swag.assert(b(1) == 101)
    Swag.assert(a(1) == 12)
    Swag.assert(b(1) == 102)
}
