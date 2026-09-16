#global private
using Swag

// The frame base the optimizer settles on can be an address derived from the
// stack pointer while other addresses still name the stack pointer directly:
// the slice built for a variadic call, and the outgoing arguments of a call
// with more than four parameters. Writes through either spelling must survive
// promotion of the frame's scalars.

#[Swag.Strict]
alias StrictAny = any

#[Swag.NoInline]
func isS32(value: any)->bool => Swag.kindOf(value) == s32 and cast #assume(s32) value == 42

#[Swag.NoInline]
func firstIsS32(values: ...)->bool => isS32(values[0])

#[Swag.Optimize(true), Swag.NoInline]
func throughVariadic()->bool
{
    let boxed = cast(StrictAny) 42's32
    return firstIsS32(boxed)
}

#[Swag.NoInline]
func weighSix(a, b, c, d, e, f: s64)->s64 => a + b * 2 + c * 3 + d * 4 + e * 5 + f * 6

#[Swag.Optimize(true), Swag.NoInline]
func passSix(x: s64)->s64
{
    let y = x + 1
    return weighSix(x, y, x, y, x + 10, y + 20)
}

#test
{
    Swag.assert(throughVariadic())
    Swag.assert(passSix(1) == 1 + 4 + 3 + 8 + 55 + 132)
    Swag.assert(passSix(-1) == -1 + 0 - 3 + 0 + 45 + 120)
}
