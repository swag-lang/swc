#global private
using Swag

struct Scale
{
    factor: s64
    limit:  s64
}

// The fields of a value parameter, string or struct, cannot change during the
// call: a loop that stores through another pointer reads them once, before it
// starts, a struct field through the address formed from the parameter.
#[Swag.Optimize(true), Swag.NoInline]
func fillScaled(out: [*] s64, count: u64, scale: Scale, text: string)->s64
{
    var total = 0's64
    for i in count
    {
        out[i] = cast(s64, i) * scale.factor
        total  += scale.limit
        total  += cast(s64, text.count)
    }

    return total
}

#test
{
    var values: [8] s64
    let total = fillScaled(&values[0], 8, Scale{3, 5}, "four")
    Swag.assert(total == 8 * (5 + 4))
    for i in 8 do
        Swag.assert(values[i] == cast(s64, i) * 3)

    Swag.assert(fillScaled(&values[0], 0, Scale{3, 5}, "four") == 0)
}
