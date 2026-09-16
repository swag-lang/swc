#global private
using Swag

// A leaf whose locals all end in registers keeps no stack frame, and a
// nonvolatile register whose uses the post-allocation cleanup forwarded away
// is no longer saved. The results must be those of the source, whether the
// function returns from one place or several, and whether a call keeps the
// frame alive.

struct Pair
{
    a, b: u64
}

#[Swag.Optimize(true), Swag.NoInline]
func swapPair(p: *Pair)
{
    let t = p.a
    p.a = p.b
    p.b = t
}

#[Swag.Optimize(true), Swag.NoInline]
func bothBelow(a, b, c, d: s64)->bool => a < b and c < d

#[Swag.Optimize(true), Swag.NoInline]
func firstAbove(values: const [*] s64, count: u64, limit: s64)->u64
{
    for i in count
    {
        if values[i] > limit do
            return i
    }

    return count
}

#[Swag.Optimize(true), Swag.NoInline]
func sumAfterCall(values: const [*] s64, count: u64, limit: s64)->s64
{
    var total = cast(s64) firstAbove(values, count, limit)
    for i in count do
        total += values[i]
    return total
}

#test
{
    var pair = Pair{1, 2}
    swapPair(&pair)
    Swag.assert(pair.a == 2 and pair.b == 1)

    Swag.assert(bothBelow(1, 2, 3, 4))
    Swag.assert(not bothBelow(2, 1, 3, 4))
    Swag.assert(not bothBelow(1, 2, 4, 3))

    let values = [5's64, -2, 9, 7]
    Swag.assert(firstAbove(&values[0], 4, 6) == 2)
    Swag.assert(firstAbove(&values[0], 4, 9) == 4)
    Swag.assert(sumAfterCall(&values[0], 4, 6) == 21)
}
