#global private

// Absolute differences compute `a - b` next to the select that the compare
// of a and b feeds, and reuse its flags. Signed and unsigned values, equal
// ones and a whole row of bytes must give the same distances.

#[Swag.Optimize(true), Swag.NoInline, Swag.Safety(.Overflow, false)]
func distance32(a, b: u32)->u32 => a > b ? a - b : b - a

#[Swag.Optimize(true), Swag.NoInline, Swag.Safety(.Overflow, false)]
func distance64(a, b: s64)->s64 => a > b ? a - b : b - a

#[Swag.Optimize(true), Swag.NoInline, Swag.Safety(.Overflow, false)]
func sumOfDistances(a, b: const [*] u8, count: u64)->u32
{
    var total = 0'u32
    for i in count
    {
        let x = cast(u32) a[i]
        let y = cast(u32) b[i]
        total += x > y ? x - y : y - x
    }
    return total
}

#[Swag.Optimize(true), Swag.NoInline, Swag.Safety(.Overflow, false)]
func lowerDistance(a, b: s32)->s32 => a < b ? b - a : a - b

func slowDistance(a, b: s64)->s64 => a > b ? a - b : b - a

#test
{
    let values = [0's64, 1, 2, 100, -1, -100, 0x7FFFFFFF, 0xFFFFFFFF]
    for a in values
    {
        for b in values
        {
            let ua = cast #wrap (u32) a
            let ub = cast #wrap (u32) b
            let expected32 = ua > ub ? ua - ub : ub - ua
            Swag.assert(distance32(ua, ub) == expected32)
            Swag.assert(distance64(a, b) == slowDistance(a, b))
            let sa = cast #wrap (s32) a
            let sb = cast #wrap (s32) b
            let expectedS = sa < sb ? cast #wrap (s32) (cast(s64) sb - cast(s64) sa) : cast #wrap (s32) (cast(s64) sa - cast(s64) sb)
            Swag.assert(lowerDistance(sa, sb) == expectedS)
        }
    }

    var left:  [6] u8 = [0, 255, 10, 7, 128, 3]
    var right: [6] u8 = [255, 0, 10, 9, 127, 200]
    Swag.assert(sumOfDistances(&left[0], &right[0], 6) == 255 + 255 + 0 + 2 + 1 + 197)
}
