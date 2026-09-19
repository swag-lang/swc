#global private

// A float select between the two values a comparison tested becomes maxss or
// minss when the test is strict. Every arrangement of the operands and arms,
// on NaNs, signed zeros, infinities and ordinary values, must return the same
// bits as the selects written out through a widened comparison.

#[Swag.Optimize(true), Swag.NoInline]
func maxGreater(a, b: f32)->f32 => a > b ? a : b
#[Swag.Optimize(true), Swag.NoInline]
func minGreater(a, b: f32)->f32 => a > b ? b : a
#[Swag.Optimize(true), Swag.NoInline]
func minLess(a, b: f32)->f32 => a < b ? a : b
#[Swag.Optimize(true), Swag.NoInline]
func maxLess(a, b: f32)->f32 => a < b ? b : a
#[Swag.Optimize(true), Swag.NoInline]
func maxGreaterEqual(a, b: f32)->f32 => a >= b ? a : b
#[Swag.Optimize(true), Swag.NoInline]
func minLessEqual(a, b: f32)->f32 => a <= b ? a : b
#[Swag.Optimize(true), Swag.NoInline]
func wideMax(a, b: f64)->f64 => a > b ? a : b
#[Swag.Optimize(true), Swag.NoInline]
func clamp01(x: f32)->f32 => x < 0.0 ? 0.0 : (x > 1.0 ? 1.0 : x)

#[Swag.Optimize(false), Swag.NoInline]
func greaterRef(a, b: f32)->bool => cast(f64) a > cast(f64) b
#[Swag.Optimize(false), Swag.NoInline]
func greaterEqualRef(a, b: f32)->bool => cast(f64) a >= cast(f64) b

func bits(x: f32)->u32 => cast #bit (u32) x

#[Swag.Safety(.All, false)]
#test
{
    let nan             = cast #bit (f32) 0x7FC00000'u32
    let negZero         = cast #bit (f32) 0x80000000'u32
    let inf             = cast #bit (f32) 0x7F800000'u32
    let values: [9] f32 = [0.0, negZero, 1.0, -1.0, 0.25, nan, inf, -inf, 2.0]

    for a in values
    {
        for b in values
        {
            Swag.assert(bits(maxGreater(a, b)) == bits(greaterRef(a, b) ? a : b))
            Swag.assert(bits(minGreater(a, b)) == bits(greaterRef(a, b) ? b : a))
            Swag.assert(bits(minLess(a, b)) == bits(greaterRef(b, a) ? a : b))
            Swag.assert(bits(maxLess(a, b)) == bits(greaterRef(b, a) ? b : a))
            Swag.assert(bits(maxGreaterEqual(a, b)) == bits(greaterEqualRef(a, b) ? a : b))
            Swag.assert(bits(minLessEqual(a, b)) == bits(greaterEqualRef(b, a) ? a : b))

            let wide = wideMax(cast(f64) a, cast(f64) b)
            Swag.assert(cast #bit (u64) wide == cast #bit (u64) (greaterRef(a, b) ? cast(f64) a : cast(f64) b))
        }

        let clamped = clamp01(a)
        Swag.assert(bits(clamped) == bits(greaterRef(0.0, a) ? 0.0'f32 : (greaterRef(a, 1.0) ? 1.0'f32 : a)))
    }
}
