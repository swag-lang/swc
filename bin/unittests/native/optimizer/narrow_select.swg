#global private

// Selects whose result is only read as a dword select dwords. The values
// selected from, including qwords with bits above the dword, must still give
// the right low half, and a qword result must stay whole.

#[Swag.Optimize(true), Swag.NoInline, Swag.Safety(.Overflow, false)]
func abs32(x: s32)->s32 => x < 0 ? -x : x

#[Swag.Optimize(true), Swag.NoInline]
func pickLow(a, b: s64, flag: bool)->s32 => cast #wrap (s32) (flag ? a : b)

#[Swag.Optimize(true), Swag.NoInline]
func pickWide(a, b: s64, flag: bool)->s64 => flag ? a : b

#[Swag.Optimize(true), Swag.NoInline]
func upper(c: u8)->u8 => c >= 'a' and c <= 'z' ? c - 32 : c

#[Swag.Optimize(true), Swag.NoInline, Swag.Safety(.Overflow, false)]
func manhattan(ax, ay, bx, by: s32)->s32
{
    let dx = ax > bx ? ax - bx : bx - ax
    let dy = ay > by ? ay - by : by - ay
    return dx + dy
}

#test
{
    Swag.assert(abs32(-4) == 4 and abs32(5) == 5 and abs32(0) == 0)
    Swag.assert(abs32(-0x7FFFFFFF - 1) == -0x7FFFFFFF - 1)
    Swag.assert(pickLow(0x1_0000_0005, -3, true) == 5)
    Swag.assert(pickLow(0x1_0000_0005, -3, false) == -3)
    Swag.assert(pickLow(-0x1_0000_0000, 7, true) == 0)
    Swag.assert(pickWide(0x1_0000_0005, -3, true) == 0x1_0000_0005)
    Swag.assert(pickWide(0x1_0000_0005, -3, false) == -3)
    for v in 0 until 256
    {
        let c        = cast(u8) v
        let expected = c >= 'a' and c <= 'z' ? c - 32 : c
        Swag.assert(upper(c) == expected)
    }
    Swag.assert(manhattan(1, 2, 4, -6) == 11)
    Swag.assert(manhattan(-100, 50, 100, 50) == 200)
}
