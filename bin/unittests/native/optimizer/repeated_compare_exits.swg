#global private

struct Cursors
{
    lo, hi: s64
}

#[Swag.Optimize(true), Swag.NoInline]
func stepInward(first, last: s64)->Cursors
{
    var lo = first
    var hi = last
    while true
    {
        if lo <= hi
        {
            lo += 3
            hi -= 2
        }

        if lo > hi do
            return {lo, hi}
    }
}

#test
{
    for first in -64's64 to 64
    {
        for last in -64's64 to 64
        {
            let trips   = last >= first ? (last - first) / 5 + 1 : 0
            let cursors = stepInward(first, last)
            Swag.assert(cursors.lo == first + 3 * trips)
            Swag.assert(cursors.hi == last - 2 * trips)
        }
    }

    // The initial taken edge must also retain the complete signed inputs.
    let empty = stepInward(0x7FFF_FFFF_FFFF_FFFF, -0x7FFF_FFFF_FFFF_FFFF)
    Swag.assert(empty.lo == 0x7FFF_FFFF_FFFF_FFFF)
    Swag.assert(empty.hi == -0x7FFF_FFFF_FFFF_FFFF)
}
