#global private

// A signed order against zero after the arithmetic that produced the value
// reads the sign flag that arithmetic left, with no compare. Countdowns,
// backward searches and wrapped sums must still answer as the compare did.

#[Swag.Optimize(true), Swag.NoInline]
func lastIndex(s: const [*] u8, n: u64, c: u8)->s64
{
    var i = cast(s64) n - 1
    while i >= 0
    {
        if s[i] == c do return i
        i -= 1
    }
    return -1
}

#[Swag.Optimize(true), Swag.NoInline]
func countDown(from: s64)->s64
{
    var steps = 0's64
    var i     = from
    while i >= 0
    {
        steps += 1
        i     -= 1
    }
    return steps
}

#[Swag.Optimize(true), Swag.NoInline]
func isNegativeAfterAdd(a, b: s32)->bool
{
    let r = cast #wrap (s32) (cast(s64) a + cast(s64) b)
    return r < 0
}

#[Swag.Optimize(true), Swag.NoInline]
func isNonNegativeAfterSub(a, b: s64)->bool
{
    let r = a - b
    return r >= 0
}

#test
{
    let text: [6] u8 = ['a', 'b', 'c', 'a', 'b', 'c']
    Swag.assert(lastIndex(&text[0], 6, 'a') == 3)
    Swag.assert(lastIndex(&text[0], 6, 'c') == 5)
    Swag.assert(lastIndex(&text[0], 6, 'z') == -1)
    Swag.assert(lastIndex(&text[0], 0, 'a') == -1)

    Swag.assert(countDown(-1) == 0)
    Swag.assert(countDown(0) == 1)
    Swag.assert(countDown(9) == 10)

    let values = [0's32, 1, -1, 0x7FFFFFFF, -0x7FFFFFFF - 1, 1000, -1000]
    for a in values
    {
        for b in values
        {
            Swag.assert(isNegativeAfterAdd(a, b) == ((cast(s64) a + cast(s64) b) & 0x80000000 != 0))
            Swag.assert(isNonNegativeAfterSub(a, b) == (cast(s64) a - cast(s64) b >= 0))
        }
    }
}
