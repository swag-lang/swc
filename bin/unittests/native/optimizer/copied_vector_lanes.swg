#global private
using Swag

#[Swag.Optimize(true), Swag.NoInline]
func updateCopiedLanes(seed: u32, count, rounds: u64)->u64
{
    var initial: [4] u32 = [seed, seed + 3, seed + 7, seed + 11]
    var result = 0'u64
    for count
    {
        var state = initial
        for rounds do
            for lane in 4 do state[lane] = (state[lane] + 17) ^ 0x10203
        result  += cast(u64, state[1]) + state[3]
        initial = state
    }
    return result
}

#[Swag.Optimize(true), Swag.NoInline]
func updateCopiedWideLanes(seed: u64, count, rounds: u64)->u64
{
    var initial: [2] u64 = [seed, seed + 0x100000003]
    var result = 0'u64
    for count
    {
        var state = initial
        for rounds do
            for lane in 2 do state[lane] = (state[lane] + 17) ^ 0x10203
        result  += state[1]
        initial = state
    }
    return result
}

#test
{
    for count in [0'u64, 1, 3, 16]
    {
        var a            = 42'u32 + 3
        var b            = 42'u32 + 11
        var wide         = 42'u64 + 0x100000003
        var expected     = 0'u64
        var expectedWide = 0'u64
        for count
        {
            for 10
            {
                a    = (a + 17) ^ 0x10203
                b    = (b + 17) ^ 0x10203
                wide = (wide + 17) ^ 0x10203
            }
            expected     += cast(u64, a) + b
            expectedWide += wide
        }
        Swag.assert(updateCopiedLanes(42, count, 10) == expected)
        Swag.assert(updateCopiedWideLanes(42, count, 10) == expectedWide)
    }
}
