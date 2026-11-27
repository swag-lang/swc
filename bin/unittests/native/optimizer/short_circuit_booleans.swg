#global private
using Swag

// A short-circuit `and` or `or` kept as a value evaluates its right side on
// every path and combines the two bytes. Every combination of the operands,
// signed and unsigned compares, and a result reused after the join must give
// the source answer.

#[Swag.Optimize(true), Swag.NoInline]
func bothBelow(a, b, c, d: s64)->bool => a < b and c < d

#[Swag.Optimize(true), Swag.NoInline]
func eitherAbove(a, b: u32, c: u32)->bool => a > c or b > c

#[Swag.Optimize(true), Swag.NoInline]
func isDigit(c: u8)->bool => c >= '0' and c <= '9'

#[Swag.Optimize(true), Swag.NoInline]
func countBoth(values: const [*] s32, count: u64, low, high: s32)->u64
{
    var total = 0_u64
    for i in count
    {
        let inside = values[i] > low and values[i] < high
        if inside
        {
            total += 2
        }
        else
        {
            total += 1
        }
    }

    return total
}

#test
{
    let samples = [-3_s64, 0, 5]
    for a in samples
    {
        for b in samples
        {
            for c in samples
            {
                for d in samples
                {
                    Swag.require(bothBelow(a, b, c, d) == ((a < b) and (c < d)))
                }
            }
        }
    }

    let words = [0_u32, 7, 0xFFFFFFFF]
    for a in words
    {
        for b in words
        {
            for c in words
            {
                Swag.require(eitherAbove(a, b, c) == ((a > c) or (b > c)))
            }
        }
    }

    for c in 256
    {
        let b = cast(u8, c)
        Swag.require(isDigit(b) == (c >= 48 and c <= 57))
    }

    let values = [1_s32, 5, 9, -2, 7]
    Swag.require(countBoth(&values[0], 5, 0, 8) == 2 + 2 + 1 + 1 + 2)
}
