// 

#global private

#[Swag.Inline]
func inlineConst()->s32 => 42

#[Swag.Inline]
func inlineIdentity(v: s32)->s32 => v

#[Swag.Inline]
func inlineAdd(a: s32, b: s32)->s32 => a + b

#[Swag.Inline]
func inlineSub(a: s32, b: s32)->s32 => a - b

#[Swag.Inline]
func inlineMul(a: s32, b: s32)->s32 => a * b

#[Swag.Inline]
func inlineDiv(a: s32, b: s32)->s32 => a / b

#[Swag.Inline]
func inlineMod(a: s32, b: s32)->s32 => a % b

#[Swag.Inline]
func inlineNeg(v: s32)->s32 => -v

#[Swag.Inline]
func inlineNamed(a: s32, b: s32, c: s32)->s32 => a + b + c

#[Swag.Inline]
func inlineNamedLocal(a: s32, b: s32, c: s32)->s32
{
    var namedTmp: s32 = a + b
    return namedTmp + c
}

#[Swag.Inline]
func inlineBranch(flag: bool, x: s32, y: s32)->s32
{
    if flag
    {
        return x
    }

    return y
}

#[Swag.Inline]
func inlineEq(a: s32, b: s32)->bool => a == b

#[Swag.Inline]
func inlineNe(a: s32, b: s32)->bool => a != b

#[Swag.Inline]
func inlineLt(a: s32, b: s32)->bool => a < b

#[Swag.Inline]
func inlineLe(a: s32, b: s32)->bool => a <= b

#[Swag.Inline]
func inlineGt(a: s32, b: s32)->bool => a > b

#[Swag.Inline]
func inlineGe(a: s32, b: s32)->bool => a >= b

#[Swag.Inline]
func inlineAnd(a: bool, b: bool)->bool => a and b

#[Swag.Inline]
func inlineOr(a: bool, b: bool)->bool => a or b

#[Swag.Inline]
func inlineNot(a: bool)->bool => !a

#[Swag.Inline]
func inlineDefault1(a: s32, b: s32 = 10)->s32 => a + b

#[Swag.Inline]
func inlineDefault2(a: s32, b: s32 = 10, c: s32 = 100)->s32 => a + b + c

#[Swag.Inline]
func inlinePack4(a: s32, b: s32, c: s32, d: s32)->s32 => a * 1000 + b * 100 + c * 10 + d

#[Swag.Inline]
func inlineSum5(a: s32, b: s32, c: s32, d: s32, e: s32)->s32 => a + b + c + d + e

#[Swag.Inline]
func inlineAddU32(a: u32, b: u32)->u32 => a + b

#[Swag.Inline]
func inlineIsNonZeroU32(v: u32)->bool => v != 0

#[Swag.Inline]
func inlineBetween(v: s32, lo: s32, hi: s32)->bool => inlineGe(v, lo) and inlineLe(v, hi)

#[Swag.Inline]
func inlineCascade(a: s32, b: s32, c: s32)->s32 => inlineAdd(a * b, c)

#[Swag.Inline]
func inlineSelect(flag: bool, a: s32, b: s32)->s32 => inlineBranch(flag, a, b)

#[Swag.Inline]
func inlineSeedS32()->s32 => 41

#[Swag.Inline]
func inlineArraySeed()->[3] s32 => [10, 42, 99]

#[Swag.Inline]
func inlineTakeS32(value: s32)->s32 => value

#[Swag.Inline]
func inlineTakeBool(value: bool)->bool => value

#test
{
    Swag.assert(inlineConst() == 42)
    Swag.assert(inlineIdentity(42) == 42)

    var a: s32 = inlineAdd(20, 22)
    Swag.assert(a == 42)

    Swag.assert(inlineSub(50, 8) == 42)
    Swag.assert(inlineMul(6, 7) == 42)
    Swag.assert(inlineDiv(126, 3) == 42)
    Swag.assert(inlineMod(212, 85) == 42)
    Swag.assert(inlineNeg(-42) == 42)
    Swag.assert(inlineNeg(42) == -42)

    var xa: s32 = 30
    var ya: s32 = 12
    Swag.assert(inlineAdd(xa, ya) == 42)
    Swag.assert(inlineAdd(10 * 2, 20 + 2) == 42)
    Swag.assert(inlineSub(inlineMul(8, 8), 22) == 42)
    Swag.assert(inlineCascade(5, 8, 2) == 42)
    Swag.assert(inlineAdd(inlineSub(100, 58), 0) == 42)
    Swag.assert(inlineAdd(inlineMul(4, 9), inlineDiv(24, 4)) == 42)

    var b: s32 = inlineNamed(a: 1, c: 40, b: 1)
    Swag.assert(b == 42)
    Swag.assert(inlineNamed(1, 1, 40) == 42)
    Swag.assert(inlineNamed(c: 10, b: 12, a: 20) == 42)
    Swag.assert(inlineNamedLocal(1, 1, 40) == 42)
    Swag.assert(inlineNamedLocal(2, 2, 38) == 42)

    Swag.assert(inlineDefault1(32) == 42)
    Swag.assert(inlineDefault1(2, 40) == 42)
    Swag.assert(inlineDefault2(32) == 142)
    Swag.assert(inlineDefault2(2, 40) == 142)
    Swag.assert(inlineDefault2(2, 20, 20) == 42)
    Swag.assert(inlineDefault2(c: 30, a: 2, b: 10) == 42)

    Swag.assert(inlinePack4(0, 0, 4, 2) == 42)
    Swag.assert(inlinePack4(a: 0, d: 2, b: 0, c: 4) == 42)
    Swag.assert(inlineSum5(8, 8, 8, 8, 10) == 42)
    Swag.assert(inlineSum5(a: 20, e: 2, b: 10, c: 5, d: 5) == 42)

    var c: s32 = inlineBranch(true, 42, 5)
    var d: s32 = inlineBranch(false, 5, 42)
    Swag.assert(c == 42)
    Swag.assert(d == 42)
    Swag.assert(inlineSelect(true, 42, 5) == 42)
    Swag.assert(inlineSelect(false, 5, 42) == 42)

    Swag.assert(inlineEq(42, 42))
    Swag.assert(!inlineEq(42, 41))
    Swag.assert(inlineNe(42, 41))
    Swag.assert(!inlineNe(42, 42))
    Swag.assert(inlineLt(41, 42))
    Swag.assert(!inlineLt(42, 42))
    Swag.assert(inlineLe(42, 42))
    Swag.assert(inlineLe(41, 42))
    Swag.assert(!inlineLe(43, 42))
    Swag.assert(inlineGt(43, 42))
    Swag.assert(!inlineGt(42, 42))
    Swag.assert(inlineGe(42, 42))
    Swag.assert(inlineGe(43, 42))
    Swag.assert(!inlineGe(41, 42))

    Swag.assert(inlineAnd(true, true))
    Swag.assert(!inlineAnd(true, false))
    Swag.assert(inlineOr(true, false))
    Swag.assert(!inlineOr(false, false))
    Swag.assert(inlineNot(false))
    Swag.assert(!inlineNot(true))

    Swag.assert(inlineBranch(inlineEq(1, 1), 42, 0) == 42)
    Swag.assert(inlineBranch(inlineEq(1, 2), 0, 42) == 42)
    Swag.assert(inlineBranch(inlineAnd(true, inlineNot(false)), 42, -1) == 42)

    Swag.assert(inlineBetween(42, 42, 42))
    Swag.assert(inlineBetween(42, 0, 100))
    Swag.assert(!inlineBetween(42, 43, 100))
    Swag.assert(!inlineBetween(42, 0, 41))

    var u: u32 = inlineAddU32(40, 2)
    Swag.assert(u == 42)
    Swag.assert(inlineAddU32(0, 0) == 0)
    Swag.assert(inlineAddU32(1, 41) == 42)
    Swag.assert(inlineIsNonZeroU32(u))
    Swag.assert(!inlineIsNonZeroU32(0))

    var fromBool: s32 = inlineBranch(inlineIsNonZeroU32(1), 42, 0)
    Swag.assert(fromBool == 42)

    Swag.assert(inlineAdd(inlineBranch(true, 20, 0), inlineBranch(false, 0, 22)) == 42)
    Swag.assert(inlineAdd(inlinePack4(0, 0, 2, 0), inlinePack4(0, 0, 2, 2)) == 42)
    Swag.assert(inlineAdd(inlineDefault1(30), inlineDefault1(1, 1)) == 42)
    Swag.assert(inlineAdd(inlineNamed(10, 10, 1), inlineNamed(a: 10, c: 10, b: 1)) == 42)

    Swag.assert(inlineTakeS32(-inlineNeg(42)) == 42)
    Swag.assert(inlineTakeS32(inlineSeedS32() + 1) == 42)
    Swag.assert(inlineTakeBool(inlineSeedS32() == 41))
    Swag.assert(inlineTakeS32(inlineArraySeed()[1]) == 42)
    Swag.assert(inlineTakeS32(cast(s32) inlineAddU32(40, 2)) == 42)
}
