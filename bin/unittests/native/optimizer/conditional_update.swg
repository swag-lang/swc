#global private
#global #[Swag.Safety(.Overflow, false)]
using Swag

// An `if` without `else` that only updates one value runs its body on every
// path and a conditional move keeps or drops the result. The body must behave
// exactly as the branch did: it may read the value before writing it, write
// the flags the move needs, or leave the value untouched on the skipping path.

#[Swag.Optimize(true), Swag.NoInline]
func countAbove(values: const [*] s32, count: u64, limit: s32)->u64
{
    var total = 0'u64
    for i in count
    {
        if values[i] > limit do
            total += 1
    }

    return total
}

#[Swag.Optimize(true), Swag.NoInline]
func sumScaledAbove(values: const [*] s32, count: u64, limit: s32)->s64
{
    var total = 0's64
    for i in count
    {
        let value = cast(s64) values[i]
        if value > limit do
            total += value * 3 + 1
    }

    return total
}

#[Swag.Optimize(true), Swag.NoInline]
func shiftWhenOdd(value: u64, count: u64)->u64
{
    var result = value
    if (count & 1) == 1 do
        result = (result << 2) ^ count
    return result
}

#[Swag.Optimize(true), Swag.NoInline]
func clampUpdate(value, limit: u32)->u32
{
    var result = value
    if result > limit do
        result -= limit
    return result
}

#test
{
    let values = [3's32, -7, 12, 12, 0, 25, -1]
    Swag.assert(countAbove(&values[0], 7, 2) == 4)
    Swag.assert(countAbove(&values[0], 7, 12) == 1)
    Swag.assert(countAbove(&values[0], 7, 100) == 0)
    Swag.assert(countAbove(&values[0], 0, 0) == 0)

    Swag.assert(sumScaledAbove(&values[0], 7, 2) == 10 + 37 + 37 + 76)
    Swag.assert(sumScaledAbove(&values[0], 7, -8) == 10 - 20 + 37 + 37 + 1 + 76 - 2)

    Swag.assert(shiftWhenOdd(5, 3) == 23)
    Swag.assert(shiftWhenOdd(5, 2) == 5)
    Swag.assert(shiftWhenOdd(0xC000000000000001, 1) == 5)

    Swag.assert(clampUpdate(10, 3) == 7)
    Swag.assert(clampUpdate(3, 3) == 3)
    Swag.assert(clampUpdate(0xFFFFFFFF, 1) == 0xFFFFFFFE)
}
