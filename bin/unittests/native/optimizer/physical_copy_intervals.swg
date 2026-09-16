#global private

#[Swag.NoInline]
func combine(a, b, mask: u64)->u64 => (a & mask) | (b & ~mask)

#[Swag.NoInline]
func acrossCall(a, b, c, d, e, f: u64)->u64
{
    let first  = combine(a, b, c)
    let second = combine(d, e, f)
    return first ^ second ^ a ^ d
}

#[Swag.NoInline]
func throughBranches(a, b, mask: u64, count: u32)->u64
{
    var result = a
    for i in count
    {
        if i & 1 == 0 do
            result = combine(result, b, mask)
        else do
            result = combine(b, result, ~mask)
    }
    return result
}

#[Swag.NoInline]
func throughDivision(a, b, mask: u64)->u64
{
    let first = combine(a, b, mask)
    return first / 7 + first % 7
}

#test
{
    let values = [0'u64, 1, 0xFFFFFFFF, 0x100000000, 0x5555555555555555, 0xAAAAAAAAAAAAAAAA, 0xFFFFFFFFFFFFFFFF]
    for a in values
    {
        for b in values
        {
            for mask in values
            {
                let selected = b ^ ((a ^ b) & mask)
                Swag.assert(combine(a, b, mask) == selected)
                Swag.assert(acrossCall(a, b, mask, b, a, ~mask) == (a ^ b))
                Swag.assert(throughBranches(a, b, mask, 0) == a)
                Swag.assert(throughBranches(a, b, mask, 5) == selected)
                Swag.assert(throughDivision(a, b, mask) == selected / 7 + selected % 7)
            }
        }
    }
}
