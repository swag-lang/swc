#global private

#[Swag.Inline]
func inlineClosureAccumulator(start: s32)->func||(s32)->s32
{
    var total = start
    return func|total|(delta: s32)->s32
    {
        total += delta
        return total
    }
}

#test
{
    let a = inlineClosureAccumulator(10)
    let b = inlineClosureAccumulator(100)

    @assert(a(1) == 11)
    @assert(b(1) == 101)
    @assert(a(1) == 12)
    @assert(b(1) == 102)
}
