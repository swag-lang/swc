#global private

// Locals addressed through a frame base the peephole already folded with the first local's
// displacement, `lea base, [rsp + C]`: every address through the base, and a plain copy of
// it, must keep pointing at the same local once the base becomes the stack pointer.

struct Pair
{
    a, b: u64
}

#[Swag.NoInline]
func fill(p: *Pair, v: u64)
{
    p.a = v
    p.b = v * 2
}

#[Swag.NoInline]
func pick(p: *Pair, first: bool)->u64 => first ? p.a : p.b

#[Swag.Optimize(true), Swag.NoInline]
func sumLocals(v: u64)->u64
{
    var first:  Pair
    var second: Pair
    fill(&first, v)
    fill(&second, v + 1)
    let other = &second
    return first.a + other.b + pick(&first, false) + pick(other, true)
}

#test
{
    for v in [0'u64, 1, 7, 1000]
        do Swag.assert(sumLocals(v) == v + (v + 1) * 2 + v * 2 + (v + 1))
}
