#global private

// A signed division or remainder by a positive constant is the unsigned one when the dividend
// cannot be negative: a mask or a shift replaces the sign-corrected sequence. The proof is
// what defines the dividend, or a test every path to the division has passed. A dividend
// that can be negative keeps the signed result, truncated toward zero.

// The loop condition proves 'cand' before the body takes its remainder.
#[Swag.NoInline]
#[Swag.Optimize(true)]
func follow(links: const [*] s64, start: s64)->s64
{
    var cand  = start
    var steps = 0's64
    while cand >= 0 and steps < 16
    {
        cand  = links[cand % 8]
        steps += 1
    }

    return cand * 100 + steps
}

// The span is tested against a positive bound before it is halved.
#[Swag.NoInline]
#[Swag.Optimize(true)]
func middle(lo, hi: s64)->s64
{
    if hi - lo > 16 do
        return lo + (hi - lo) / 2
    return -1
}

// A mask and a zero extension both leave the top bit clear.
#[Swag.NoInline]
#[Swag.Optimize(true)]
func afterMask(value: s64)->s64
{
    let masked = value & 0xFFFF
    return masked % 10 + masked / 16
}

#[Swag.NoInline]
#[Swag.Optimize(true)]
func afterWidening(value: u32)->s64
{
    let wide = cast(s64, value)
    return wide % 1000 + wide / 8
}

// Nothing is known here: the results keep the sign of the dividend.
#[Swag.NoInline]
#[Swag.Optimize(true)]
func remainder(value: s64)->s64 => value % 8

#[Swag.NoInline]
#[Swag.Optimize(true)]
func half(value: s64)->s64 => value / 2

// A remainder only tested for zero reads the low bits of the dividend, whatever its sign.
#[Swag.NoInline]
#[Swag.Optimize(true)]
func isMultipleOf8(value: s64)->bool => value % 8 == 0

#[Swag.NoInline]
#[Swag.Optimize(true)]
func alternate(count: s64)->s64
{
    var sum = 0's64
    for i in -count until count
    {
        if i % 2 == 0 do
            sum += i
        else do
            sum -= 3
    }

    return sum
}

// The test is on another value.
#[Swag.NoInline]
#[Swag.Optimize(true)]
func guardedByOther(value, other: s64)->s64
{
    if other >= 0 do
        return value % 8
    return 0
}

// The tested value changes before the remainder.
#[Swag.NoInline]
#[Swag.Optimize(true)]
func changedAfterTest(value: s64)->s64
{
    var moved = value
    if moved >= 0
    {
        moved -= 20
        return moved % 8
    }

    return 1
}

#test
{
    let links: [8] s64 = [3, -1, 5, 6, 0, 7, 1, 2]
    Swag.require(follow(&links[0], 4) == -95)
    Swag.require(follow(&links[0], 12) == -95)
    Swag.require(follow(&links[0], -3) == -300)
    Swag.require(follow(&links[0], 2) == 516)

    Swag.require(middle(10, 100) == 55)
    Swag.require(middle(-101, 0) == -51)
    Swag.require(middle(0, 10) == -1)

    Swag.require(afterMask(-1) == 4100)
    Swag.require(afterMask(0x12345) == 573)
    Swag.require(afterWidening(0xFFFFFFFF) == 536871206)

    Swag.require(remainder(-13) == -5 and remainder(13) == 5)
    Swag.require(half(-7) == -3 and half(7) == 3)
    Swag.require(isMultipleOf8(-16) and isMultipleOf8(24) and isMultipleOf8(0))
    Swag.require(not isMultipleOf8(-13) and not isMultipleOf8(7) and not isMultipleOf8(-1))
    Swag.require(alternate(5) == -15)
    Swag.require(guardedByOther(-13, 4) == -5 and guardedByOther(-13, -1) == 0)
    Swag.require(changedAfterTest(5) == -7 and changedAfterTest(30) == 2 and changedAfterTest(-4) == 1)
}
