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
func inlineNot(a: bool)->bool => not a

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
    Swag.require(inlineConst() == 42)
    Swag.require(inlineIdentity(42) == 42)

    var a: s32 = inlineAdd(20, 22)
    Swag.require(a == 42)

    Swag.require(inlineSub(50, 8) == 42)
    Swag.require(inlineMul(6, 7) == 42)
    Swag.require(inlineDiv(126, 3) == 42)
    Swag.require(inlineMod(212, 85) == 42)
    Swag.require(inlineNeg(-42) == 42)
    Swag.require(inlineNeg(42) == -42)

    var xa: s32 = 30
    var ya: s32 = 12
    Swag.require(inlineAdd(xa, ya) == 42)
    Swag.require(inlineAdd(10 * 2, 20 + 2) == 42)
    Swag.require(inlineSub(inlineMul(8, 8), 22) == 42)
    Swag.require(inlineCascade(5, 8, 2) == 42)
    Swag.require(inlineAdd(inlineSub(100, 58), 0) == 42)
    Swag.require(inlineAdd(inlineMul(4, 9), inlineDiv(24, 4)) == 42)

    var b: s32 = inlineNamed(a: 1, c: 40, b: 1)
    Swag.require(b == 42)
    Swag.require(inlineNamed(1, 1, 40) == 42)
    Swag.require(inlineNamed(c: 10, b: 12, a: 20) == 42)
    Swag.require(inlineNamedLocal(1, 1, 40) == 42)
    Swag.require(inlineNamedLocal(2, 2, 38) == 42)

    Swag.require(inlineDefault1(32) == 42)
    Swag.require(inlineDefault1(2, 40) == 42)
    Swag.require(inlineDefault2(32) == 142)
    Swag.require(inlineDefault2(2, 40) == 142)
    Swag.require(inlineDefault2(2, 20, 20) == 42)
    Swag.require(inlineDefault2(c: 30, a: 2, b: 10) == 42)

    Swag.require(inlinePack4(0, 0, 4, 2) == 42)
    Swag.require(inlinePack4(a: 0, d: 2, b: 0, c: 4) == 42)
    Swag.require(inlineSum5(8, 8, 8, 8, 10) == 42)
    Swag.require(inlineSum5(a: 20, e: 2, b: 10, c: 5, d: 5) == 42)

    var c: s32 = inlineBranch(true, 42, 5)
    var d: s32 = inlineBranch(false, 5, 42)
    Swag.require(c == 42)
    Swag.require(d == 42)
    Swag.require(inlineSelect(true, 42, 5) == 42)
    Swag.require(inlineSelect(false, 5, 42) == 42)

    Swag.require(inlineEq(42, 42))
    Swag.require(not inlineEq(42, 41))
    Swag.require(inlineNe(42, 41))
    Swag.require(not inlineNe(42, 42))
    Swag.require(inlineLt(41, 42))
    Swag.require(not inlineLt(42, 42))
    Swag.require(inlineLe(42, 42))
    Swag.require(inlineLe(41, 42))
    Swag.require(not inlineLe(43, 42))
    Swag.require(inlineGt(43, 42))
    Swag.require(not inlineGt(42, 42))
    Swag.require(inlineGe(42, 42))
    Swag.require(inlineGe(43, 42))
    Swag.require(not inlineGe(41, 42))

    Swag.require(inlineAnd(true, true))
    Swag.require(not inlineAnd(true, false))
    Swag.require(inlineOr(true, false))
    Swag.require(not inlineOr(false, false))
    Swag.require(inlineNot(false))
    Swag.require(not inlineNot(true))

    Swag.require(inlineBranch(inlineEq(1, 1), 42, 0) == 42)
    Swag.require(inlineBranch(inlineEq(1, 2), 0, 42) == 42)
    Swag.require(inlineBranch(inlineAnd(true, inlineNot(false)), 42, -1) == 42)

    Swag.require(inlineBetween(42, 42, 42))
    Swag.require(inlineBetween(42, 0, 100))
    Swag.require(not inlineBetween(42, 43, 100))
    Swag.require(not inlineBetween(42, 0, 41))

    var u: u32 = inlineAddU32(40, 2)
    Swag.require(u == 42)
    Swag.require(inlineAddU32(0, 0) == 0)
    Swag.require(inlineAddU32(1, 41) == 42)
    Swag.require(inlineIsNonZeroU32(u))
    Swag.require(not inlineIsNonZeroU32(0))

    var fromBool: s32 = inlineBranch(inlineIsNonZeroU32(1), 42, 0)
    Swag.require(fromBool == 42)

    Swag.require(inlineAdd(inlineBranch(true, 20, 0), inlineBranch(false, 0, 22)) == 42)
    Swag.require(inlineAdd(inlinePack4(0, 0, 2, 0), inlinePack4(0, 0, 2, 2)) == 42)
    Swag.require(inlineAdd(inlineDefault1(30), inlineDefault1(1, 1)) == 42)
    Swag.require(inlineAdd(inlineNamed(10, 10, 1), inlineNamed(a: 10, c: 10, b: 1)) == 42)

    Swag.require(inlineTakeS32(-inlineNeg(42)) == 42)
    Swag.require(inlineTakeS32(inlineSeedS32() + 1) == 42)
    Swag.require(inlineTakeBool(inlineSeedS32() == 41))
    Swag.require(inlineTakeS32(inlineArraySeed()[1]) == 42)
    Swag.require(inlineTakeS32(cast(s32, inlineAddU32(40, 2))) == 42)
}
