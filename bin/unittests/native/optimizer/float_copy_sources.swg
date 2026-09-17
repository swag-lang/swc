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

#test
{
    Swag.assert(lerp(1, 3, 0.5) == 2)
    Swag.assert(lerp(-2, 2, 0.25) == -1)
    Swag.assert(lerp64(10, 20, 0.1) == 11)
    Swag.assert(reversed(5, 1, 2) == 0)
    Swag.assert(reversed(1, 5, 4) == 5)
    Swag.assert(squares(2, 3) == 27)
}
