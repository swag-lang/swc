#global private
using Swag

// A counted loop is unrolled to fixed offsets. The indexed memory operations
// may already have absorbed their load/store pairs before the index folds.
#[Swag.Optimize(true), Swag.NoInline]
func xorWords(values: [*] u32, mask: u32)
{
    for i in 16 do values[i] ^= mask
}

#[Swag.Optimize(true), Swag.NoInline]
func incrementWords(values: [*] u32)
{
    for i in 16 do values[i] += 1
}

#[Swag.Optimize(true), Swag.NoInline]
func decrementWords(values: [*] u32)
{
    for i in 16 do values[i] -= 1
}

#[Swag.Optimize(true), Swag.NoInline]
func xorAt(values: [*] u32, index: u64, mask: u32)
{
    values[index] ^= mask
}

#test
{
    var values: [18] u32
    for i in 18 do values[i] = cast(u32, i)
    xorWords(&values[1], 0x35)
    incrementWords(&values[1])
    decrementWords(&values[1])
    xorAt(&values[0], 17, 0x72)
    Swag.assert(values[0] == 0)
    for i in 1 until 17 do Swag.assert(values[i] == (cast(u32, i) ^ 0x35))
    Swag.assert(values[17] == (17 ^ 0x72))
}
