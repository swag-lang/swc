#global private
using Swag

// A float copied only to be an operand is read from where it came from.
// Operand order, both widths, and a copy whose source is written in between
// must keep the source results.

#[Swag.Optimize(true), Swag.NoInline]
func lerp(a, b, t: f32)->f32 => a + (b - a) * t

#[Swag.Optimize(true), Swag.NoInline]
func lerp64(a, b, t: f64)->f64 => a + (b - a) * t

#[Swag.Optimize(true), Swag.NoInline]
func reversed(a, b, c: f32)->f32 => c - (a - b) / c

#[Swag.Optimize(true), Swag.NoInline]
func squares(a, b: f64)->f64
{
    var x = a
    let y = x * b
    x = y - a
    return x * y + b
}

#[Swag.Optimize(true), Swag.NoInline]
func select32(a, b: f32, pickA: bool)->f32 => pickA ? a : b

#[Swag.Optimize(true), Swag.NoInline]
func select64(a, b: f64, pickA: bool)->f64 => pickA ? a : b

#[Swag.Optimize(true), Swag.NoInline]
func minimum32(a, b: f32)->f32 => a < b ? a : b

#[Swag.Optimize(true), Swag.NoInline]
func maximum32(a, b: f32)->f32 => a > b ? a : b

#[Swag.Optimize(true), Swag.NoInline]
func minimum64(a, b: f64)->f64 => a < b ? a : b

#[Swag.Optimize(true), Swag.NoInline]
func maximum64(a, b: f64)->f64 => a > b ? a : b

#[Swag.Optimize(true), Swag.NoInline]
func negate32(a: f32)->f32 => -a

#[Swag.Optimize(true), Swag.NoInline]
func negate64(a: f64)->f64 => -a

#test
{
    Swag.require(lerp(1, 3, 0.5) == 2)
    Swag.require(lerp(-2, 2, 0.25) == -1)
    Swag.require(lerp64(10, 20, 0.1) == 11)
    Swag.require(reversed(5, 1, 2) == 0)
    Swag.require(reversed(1, 5, 4) == 5)
    Swag.require(squares(2, 3) == 27)
    Swag.require(select32(1.25, 2.5, true) == 1.25)
    Swag.require(select32(1.25, 2.5, false) == 2.5)
    Swag.require(select64(-3.5, 7.25, true) == -3.5)
    Swag.require(select64(-3.5, 7.25, false) == 7.25)
    Swag.require(minimum32(1.25, 2.5) == 1.25)
    Swag.require(maximum32(1.25, 2.5) == 2.5)
    Swag.require(minimum64(7.25, -3.5) == -3.5)
    Swag.require(maximum64(7.25, -3.5) == 7.25)

    const minNumber = minimum32(Swag.F32.NaN, 2)
    const minNaN    = minimum32(2, Swag.F32.NaN)
    const maxNumber = maximum32(Swag.F32.NaN, 2)
    const maxNaN    = maximum32(2, Swag.F32.NaN)
    Swag.require(minNumber == 2 and minNaN != minNaN)
    Swag.require(maxNumber == 2 and maxNaN != maxNaN)

    Swag.require(negate32(1.25) == -1.25)
    Swag.require(negate64(-3.5) == 3.5)
    Swag.require(cast #bit (u32, negate32(0.0)) == 0x80000000)
    Swag.require(cast #bit (u64, negate64(0.0)) == 0x8000000000000000)
    const negatedNaN = negate32(Swag.F32.NaN)
    Swag.require(negatedNaN != negatedNaN)
}
