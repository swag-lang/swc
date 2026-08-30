#global private

#[Swag.Inline]
func inlineClosureAccumulator(start: s32)->func||(s32)->s32
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
    let a = inlineClosureAccumulator(10)
    let b = inlineClosureAccumulator(100)

    Swag.assert(a(1) == 11)
    Swag.assert(b(1) == 101)
    Swag.assert(a(1) == 12)
    Swag.assert(b(1) == 102)
}
