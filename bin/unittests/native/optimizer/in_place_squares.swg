#global private

// A square, or a doubling, of a value nothing reads afterwards runs on that
// value in place. Squares of differences, a loop accumulating squares, a
// value still read after its square, and qword squares must agree with the
// products computed through a variable factor.

#[Swag.Optimize(true), Swag.NoInline]
func distSq(x0, y0, x1, y1: s32)->s32
{
    let dx = x1 - x0
    let dy = y1 - y0
    return dx * dx + dy * dy
}
#[Swag.Optimize(true), Swag.NoInline]
func squareAndKeep(x: s32, out: *s32)->s32
{
    let v = x + 3
    out[] = v
    return v * v + v
}
#[Swag.Optimize(true), Swag.NoInline]
func sumSquares(a: const [*] s32, n: u64)->s64
{
    var sum = 0's64
    for i in n
    {
        let v = cast(s64) (a[i] - 1)
        sum += v * v
    }
    return sum
}
#[Swag.Optimize(true), Swag.NoInline]
func wideSquare(x: u64)->u64
{
    let v = x ^ 0x55
    return v * #wrap v
}
#[Swag.Optimize(true), Swag.NoInline]
func doubled(x: u32)->u32
{
    let v = x | 1
    return v + #wrap v
}
#[Swag.Optimize(true), Swag.NoInline]
func powerFour(x: s32)->s32
{
    let v = x * #wrap x
    return v * #wrap v
}

#[Swag.NoInline]
func mul32(a, b: s32)->s32 => a * #wrap b
#[Swag.NoInline]
func mul64(a, b: u64)->u64 => a * #wrap b

#test
{
    for i in -20 until 20
    {
        for j in -20 until 20
        {
            let dx = j - i
            let dy = i * 3 - j
            Swag.assert(distSq(i, j, j, i * 3) == mul32(dx, dx) + mul32(dy, dy))
        }

        var kept = 0's32
        Swag.assert(squareAndKeep(i, &kept) == mul32(i + 3, i + 3) + i + 3)
        Swag.assert(kept == i + 3)
        Swag.assert(powerFour(i) == mul32(mul32(i, i), mul32(i, i)))
        Swag.assert(doubled(cast #wrap (u32) i) == (cast #wrap (u32) i | 1) * #wrap 2)
    }

    var values: [5] s32 = [1, -2, 30000, -30000, 7]
    Swag.assert(sumSquares(&values[0], 5) == 0 + 9 + 29999 * 29999 + 30001 * 30001 + 36)

    for x in [0'u64, 1, 0x55, 0xFFFFFFFF, 0x1234567890ABCDEF, 0xFFFFFFFFFFFFFFFF] do
        Swag.assert(wideSquare(x) == mul64(x ^ 0x55, x ^ 0x55))
}
