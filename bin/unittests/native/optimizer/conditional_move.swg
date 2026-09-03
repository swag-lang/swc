#global private

// Integer selects lower to a compare and a conditional move instead of a
// branch: a ternary, a select with constant arms, a nested clamp, and the
// same shapes inside a loop. The arm of a select that reads memory the
// condition guards must keep its branch, or the load would run on the path
// that never reaches it.

#[Swag.Optimize(true)]
func selectMin(a, b: s32)->s32 => a < b ? a : b

#[Swag.Optimize(true)]
func selectMaxU64(a, b: u64)->u64 => a > b ? a : b

#[Swag.Optimize(true)]
func selectConstant(flag: bool)->s32 => flag ? 7 : 9

#[Swag.Optimize(true)]
func clampByte(v: s32)->s32 => v < 0 ? 0 : (v > 255 ? 255 : v)

#[Swag.Optimize(true)]
func selectGuardedLoad(buf: [*] s32, i, n: u64)->s32 => i < n ? buf[i] : -1

#[Swag.Optimize(true)]
func selectWithArithmetic(a, b: s32)->s32 => a < b ? a + 1 : b * 2

#[Swag.Optimize(true)]
func clampLoop(dst: [*] u8, src: [*] s32, n: u64)
{
    for i in 0 until n
    {
        var v = src[i]
        v      = v < 0 ? 0 : (v > 255 ? 255 : v)
        dst[i] = cast(u8) v
    }
}

// The same selects written as early returns: each `if … do return` is a
// triangle whose body ends the function, and the chain folds into one
// return fed by conditional moves.
#[Swag.Optimize(true)]
func clampEarly(v, lo, hi: s32)->s32
{
    if v < lo do return lo
    if v > hi do return hi
    return v
}

#[Swag.Optimize(true)]
func absEarly(v: s32)->s32
{
    if v < 0 do return -v
    return v
}

#[Swag.Optimize(true)]
func selectEarlyConstant(count: u64)->u64
{
    if count == 0 do return 1
    return count * 2
}

#[Swag.Optimize(true)]
func absDiffSum(a, b: [*] s32, n: u64)->s64
{
    var sum = 0's64
    for i in 0 until n
    {
        let d = a[i] - b[i]
        sum += d < 0 ? -d : d
    }

    return sum
}

#test
{
    Swag.assert(selectMin(3, 5) == 3)
    Swag.assert(selectMin(5, 3) == 3)
    Swag.assert(selectMin(-7, 7) == -7)
    Swag.assert(selectMaxU64(3, 5) == 5)
    Swag.assert(selectMaxU64(0xFFFF_FFFF_FFFF_FFFF, 5) == 0xFFFF_FFFF_FFFF_FFFF)
    Swag.assert(selectConstant(true) == 7)
    Swag.assert(selectConstant(false) == 9)
    Swag.assert(clampByte(-5) == 0)
    Swag.assert(clampByte(300) == 255)
    Swag.assert(clampByte(77) == 77)
    var cells: [2] s32 = [42, 43]
    Swag.assert(selectGuardedLoad(&cells[0], 1, 2) == 43)
    Swag.assert(selectGuardedLoad(&cells[0], 0x7FFF_FFFF_FFFF, 2) == -1)
    Swag.assert(selectWithArithmetic(1, 2) == 2)
    Swag.assert(selectWithArithmetic(5, 2) == 4)

    var src: [4] s32 = [-5, 10, 300, 255]
    var dst: [4] u8
    clampLoop(&dst[0], &src[0], 4)
    Swag.assert(dst[0] == 0 and dst[1] == 10 and dst[2] == 255 and dst[3] == 255)

    var a: [4] s32 = [1, 9, -3, 4]
    var b: [4] s32 = [4, 2, 3, 4]
    Swag.assert(absDiffSum(&a[0], &b[0], 4) == 3 + 7 + 6 + 0)

    Swag.assert(clampEarly(-5, 0, 10) == 0)
    Swag.assert(clampEarly(50, 0, 10) == 10)
    Swag.assert(clampEarly(5, 0, 10) == 5)
    Swag.assert(clampEarly(-2147483648, -10, 10) == -10)
    Swag.assert(absEarly(-3) == 3)
    Swag.assert(absEarly(4) == 4)
    Swag.assert(absEarly(0) == 0)
    Swag.assert(selectEarlyConstant(0) == 1)
    Swag.assert(selectEarlyConstant(21) == 42)
}
