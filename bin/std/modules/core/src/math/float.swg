#global public
#global namespace Math

// Provides mathematical constants in the floating-point type `T`.
//
// Use the `ConstF32` and `ConstF64` aliases rather than naming `T`.
struct(T) Const
{
    const Pi:         T = 3.14159265358979323846264338327950288     // Ratio of a circle's circumference to its diameter
    const E:          T = 2.71828182845904523536028747135266250     // Euler's number, the base of the natural logarithm
    const TwoPi:      T = 2 * Pi                       // Two times Pi, a full turn in radians
    const PiBy2:      T = Pi / 2                       // Pi divided by 2, a quarter turn in radians
    const PiBy3:      T = Pi / 3                       // Pi divided by 3
    const PiBy4:      T = Pi / 4                       // Pi divided by 4
    const PiBy6:      T = Pi / 6                       // Pi divided by 6
    const PiBy8:      T = Pi / 8                       // Pi divided by 8
    const ThreePiBy4: T = 3 * Pi / 4                   // Three times Pi divided by 4
    const OneByPi:    T = 1 / Pi                       // Reciprocal of Pi
    const TwoByPi:    T = 2 / Pi                       // Two divided by Pi
    const Sqrt2:      T = sqrt(cast(T) 2)              // Square root of 2
    const OneBySqrt2: T = 1 / Sqrt2                    // Reciprocal of the square root of 2
    const Ln2:        T = log(cast(T) 2)               // Natural logarithm of 2
    const Ln10:       T = log(cast(T) 10)              // Natural logarithm of 10
    const Log2E:      T = log2(E)                      // Base-two logarithm of Euler's number
    const Log10E:     T = log10(E)                     // Base-ten logarithm of Euler's number
    const Epsilon:    T = 1e-06                        // Default absolute tolerance of the epsilon comparisons
}

// Names the mathematical constants in `f32` precision.
alias ConstF32 = Const'f32

// Names the mathematical constants in `f64` precision.
alias ConstF64 = Const'f64

#[Swag.ConstExpr, Swag.Inline]
{
    // Returns the sign of `x`: -1 when negative, 1 when positive, and 0 for zero.
    func sign(x: f32) => cast(f32) (x > 0) - cast(f32) (x < 0)
    func sign(x: f64) => cast(f64) (x > 0) - cast(f64) (x < 0)

    // Returns the magnitude of `x` carrying the sign of `y`.
    //
    // Only the sign bit moves, so a NaN keeps its payload and a zero takes the sign it is given.
    func copysign(x, y: f32)->f32 => cast #bit (f32) ((cast #bit (u32) x & 0x7FFF_FFFF) | (cast #bit (u32) y & 0x8000_0000))
    func copysign(x, y: f64)->f64 => cast #bit (f64) ((cast #bit (u64) x & 0x7FFF_FFFF_FFFF_FFFF) | (cast #bit (u64) y & 0x8000_0000_0000_0000))

    // Returns `x` clamped to the range [0, 1].
    func saturate(x: f32) => clamp(x, 0'f32, 1'f32)
    func saturate(x: f64) => clamp(x, 0'f64, 1'f64)

    // Returns the linear interpolation from `x` to `y` at `factor`.
    //
    // A `factor` of 0 gives `x` and 1 gives `y`. It is not clamped, so other values extrapolate.
    func lerp(x, y, factor: f32) => x + factor * (y - x)
    func lerp(x, y, factor: f64) => x + factor * (y - x)

    // Returns the cubic interpolation between `b` and `c` at `t`, shaped by the outer samples `a` and `d`.
    //
    // A `t` of 0 gives `b` and 1 gives `c`; `a` precedes `b` and `d` follows `c` in the sampled
    // sequence.
    func cubicLerp(a, b, c, d, t: f32)->f32
    {
        let p = (d - c) - (a - b)
        return t * t * t * p + t * t * ((a - b) - p) + t * (c - a) + b
    }

    func cubicLerp(a, b, c, d, t: f64)->f64
    {
        let p = (d - c) - (a - b)
        return t * t * t * p + t * t * ((a - b) - p) + t * (c - a) + b
    }

    // Returns the smooth Hermite easing `3t² - 2t³` of `t`.
    //
    // It rises from 0 at 0 to 1 at 1 with a zero slope at both ends. `t` is not clamped; use
    // [[Core.Math.smoothstep]] to map and clamp a range first.
    func interpHermite(t: f32) => t * t * (3 - 2 * t)
    func interpHermite(t: f64) => t * t * (3 - 2 * t)

    // Returns the quintic easing `6t⁵ - 15t⁴ + 10t³` of `t`.
    //
    // It rises from 0 at 0 to 1 at 1 with zero slope and zero curvature at both ends. `t` is not
    // clamped.
    func interpQuintic(t: f32) => t * t * t * (t * (t * 6 - 15) + 10)
    func interpQuintic(t: f64) => t * t * t * (t * (t * 6 - 15) + 10)

    // Returns the fractional part of `x`, computed as `x - floor(x)`.
    //
    // The result lies within [0, 1) for negative values too, so `fract(-0.25)` is 0.75.
    func fract(x: f32)->f32 => x - floor(x)
    func fract(x: f64)->f64 => x - floor(x)

    // Returns `current` moved toward `target` by at most `speed`.
    //
    // The result is exactly `target` once that is within `speed`.
    func moveTowards(current, target, speed: f32)->f32
    {
        let distance = target - current
        if abs(distance) <= speed do
            return target
        return current + sign(distance) * speed
    }

    func moveTowards(current, target, speed: f64)->f64
    {
        let distance = target - current
        if abs(distance) <= speed do
            return target
        return current + sign(distance) * speed
    }

    // Returns `current` moved toward `target` along a critically damped spring over `deltaTime`.
    //
    // `smoothTime` is roughly the time the spring takes to reach the target, in the unit of
    // `deltaTime`, and is raised to at least 0.0001. `currentVelocity` carries the velocity from
    // one call to the next and is updated in place. The result never overshoots `target`.
    func(T) smoothDamp(current, target: T, currentVelocity: *T, smoothTime, deltaTime: T)->T
    {
        // Solve the critically damped spring exactly over this time step.
        let smoothTimeActual = Math.max(0.0001, smoothTime)
        let omega            = 2.0 / smoothTimeActual
        let displacement     = current - target
        let velocity         = currentVelocity[]
        let offset           = (velocity + omega * displacement) * deltaTime
        let decay            = Math.exp(-omega * deltaTime)
        currentVelocity[] = (velocity - omega * offset) * decay
        var result = target + (displacement + offset) * decay

        // A large incoming velocity can still cross the target.
        if (target - current > 0.0) == (result > target)
        {
            result = target
            currentVelocity[] = 0
        }

        return result
    }

    // Returns the angle `x`, given in radians, converted to degrees.
    func toDegrees(x: f32) => x * 57.295779513082320876798154814105'f32
    func toDegrees(x: f64) => x * (180'f64 / ConstF64.Pi)

    // Returns the angle `x`, given in degrees, converted to radians.
    func toRadians(x: f32) => x * 0.017453292519943295769236907684886'f32
    func toRadians(x: f64) => x * (ConstF64.Pi / 180'f64)

    // Returns whether `x` is closer to zero than `eps`.
    func isZeroEpsilon(x: f32, eps = ConstF32.Epsilon) => abs(x) < eps
    func isZeroEpsilon(x: f64, eps = ConstF64.Epsilon) => abs(x) < eps

    // Returns whether `x` and `y` differ by less than `eps`.
    //
    // The tolerance is absolute, so it suits values of known magnitude rather than arbitrary ones.
    func isEqualEpsilon(x, y: f32, eps = ConstF32.Epsilon) => abs(x - y) < eps
    func isEqualEpsilon(x, y: f64, eps = ConstF64.Epsilon) => abs(x - y) < eps

    // Returns whether `x` is NaN.
    #[Swag.Safety(.NaN, false)]
    func isNaN(x: f32) => x != x
    #[Swag.Safety(.NaN, false)]
    func isNaN(x: f64) => x != x

    // Returns whether `value` is finite, neither infinite nor NaN.
    func isFinite(value: f32)->bool
    {
        let bits = cast #bit (u32) value
        return (bits & 0x7F800000'u32) != 0x7F800000'u32
    }

    func isFinite(value: f64)->bool
    {
        let bits = cast #bit (u64) value
        return (bits & 0x7FF0000000000000'u64) != 0x7FF0000000000000'u64
    }

    // Returns the smooth Hermite step of `x` from `edge0` to `edge1`.
    //
    // The result is 0 up to `edge0`, 1 from `edge1` on, and eases between them like
    // [[Core.Math.interpHermite]]. The two edges must differ.
    func smoothstep(edge0, edge1, x: f32)->f32
    {
        let t = clamp((x - edge0) / (edge1 - edge0), 0'f32, 1'f32)
        return t * t * (3 - 2 * t)
    }

    func smoothstep(edge0, edge1, x: f64)->f64
    {
        let t = clamp((x - edge0) / (edge1 - edge0), 0'f64, 1'f64)
        return t * t * (3 - 2 * t)
    }

    // Returns `val` mapped linearly from the range [`minSrc`, `maxSrc`] to [`minDst`, `maxDst`].
    //
    // The result is not clamped, and `minSrc` and `maxSrc` must differ.
    func map(val, minSrc, maxSrc, minDst, maxDst: f32)->f32
    {
        let r = (val - minSrc) / (maxSrc - minSrc)
        return minDst + r * (maxDst - minDst)
    }

    func map(val, minSrc, maxSrc, minDst, maxDst: f64)->f64
    {
        let r = (val - minSrc) / (maxSrc - minSrc)
        return minDst + r * (maxDst - minDst)
    }

    // Returns the smallest power of ten, at least 1, that is strictly greater than `value`.
    //
    // Every `value` below 1 answers 1.
    func nextPowerOfTen(value: f32)->f32
    {
        if value < 1 do
            return 1'f32
        return pow(10'f32, floor(log10(value)) + 1)
    }

    func nextPowerOfTen(value: f64)->f64
    {
        if value < 1 do
            return 1'f64
        return pow(10'f64, floor(log10(value)) + 1)
    }
}

#[Swag.ConstExpr, Swag.Inline]
{
    // Returns the angle of the point (`x`, `y`) from the positive X axis, in radians within [-π, π].
    func atan2(y, x: f32) => Swag.atan2(y, x)
    func atan2(y, x: f64) => Swag.atan2(y, x)

    // Returns the square root of `x`.
    func sqrt(x: f32) => Swag.sqrt(x)
    func sqrt(x: f64) => Swag.sqrt(x)

    // Returns the sine of the angle `x`, in radians.
    func sin(x: f32) => Swag.sin(x)
    func sin(x: f64) => Swag.sin(x)

    // Returns the cosine of the angle `x`, in radians.
    func cos(x: f32) => Swag.cos(x)
    func cos(x: f64) => Swag.cos(x)

    // Returns the tangent of the angle `x`, in radians.
    func tan(x: f32) => Swag.tan(x)
    func tan(x: f64) => Swag.tan(x)

    // Returns the hyperbolic sine of `x`.
    func sinh(x: f32) => Swag.sinh(x)
    func sinh(x: f64) => Swag.sinh(x)

    // Returns the hyperbolic cosine of `x`.
    func cosh(x: f32) => Swag.cosh(x)
    func cosh(x: f64) => Swag.cosh(x)

    // Returns the hyperbolic tangent of `x`.
    func tanh(x: f32) => Swag.tanh(x)
    func tanh(x: f64) => Swag.tanh(x)

    // Returns the arc sine of `x`, in radians within [-π/2, π/2].
    func asin(x: f32) => Swag.asin(x)
    func asin(x: f64) => Swag.asin(x)

    // Returns the arc cosine of `x`, in radians within [0, π].
    func acos(x: f32) => Swag.acos(x)
    func acos(x: f64) => Swag.acos(x)

    // Returns the arc tangent of `x`, in radians within [-π/2, π/2].
    func atan(x: f32) => Swag.atan(x)
    func atan(x: f64) => Swag.atan(x)

    // Returns the natural logarithm of `x`.
    func log(x: f32) => Swag.log(x)
    func log(x: f64) => Swag.log(x)

    // Returns the base-two logarithm of `x`.
    func log2(x: f32) => Swag.log2(x)
    func log2(x: f64) => Swag.log2(x)

    // Returns the base-ten logarithm of `x`.
    func log10(x: f32) => Swag.log10(x)
    func log10(x: f64) => Swag.log10(x)

    // Returns `x` rounded down to an integer value.
    func floor(x: f32) => Swag.floor(x)
    func floor(x: f64) => Swag.floor(x)

    // Returns `x` rounded up to an integer value.
    func ceil(x: f32) => Swag.ceil(x)
    func ceil(x: f64) => Swag.ceil(x)

    // Returns `x` rounded toward zero to an integer value.
    func trunc(x: f32) => Swag.trunc(x)
    func trunc(x: f64) => Swag.trunc(x)

    // Returns `x` rounded to the nearest integer value, halfway cases away from zero.
    func round(x: f32) => Swag.round(x)
    func round(x: f64) => Swag.round(x)

    // Returns `x` rounded down and converted to `s32`.
    func floorS32(x: f32) => cast(s32) Swag.floor(x)

    // Returns `x` rounded down and converted to `s64`.
    func floorS64(x: f64) => cast(s64) Swag.floor(x)

    // Returns `x` rounded up and converted to `s32`.
    func ceilS32(x: f32) => cast(s32) Swag.ceil(x)

    // Returns `x` rounded up and converted to `s64`.
    func ceilS64(x: f64) => cast(s64) Swag.ceil(x)

    // Returns `x` rounded toward zero and converted to `s32`.
    func truncS32(x: f32) => cast(s32) Swag.trunc(x)

    // Returns `x` rounded toward zero and converted to `s64`.
    func truncS64(x: f64) => cast(s64) Swag.trunc(x)

    // Returns `x` rounded to the nearest integer, halfway cases away from zero, and converted to `s32`.
    func roundS32(x: f32) => cast(s32) Swag.round(x)

    // Returns `x` rounded to the nearest integer, halfway cases away from zero, and converted to `s64`.
    func roundS64(x: f64) => cast(s64) Swag.round(x)

    // Returns the absolute value of `x`.
    func abs(x: f32) => Swag.abs(x)
    func abs(x: f64) => Swag.abs(x)

    // Returns the smaller of `x` and `y`.
    func min(x, y: f32) => Swag.min(x, y)
    func min(x, y: f64) => Swag.min(x, y)

    // Returns the larger of `x` and `y`.
    func max(x, y: f32) => Swag.max(x, y)
    func max(x, y: f64) => Swag.max(x, y)

    // Returns Euler's number raised to the power `x`.
    func exp(x: f32) => Swag.exp(x)
    func exp(x: f64) => Swag.exp(x)

    // Returns two raised to the power `x`.
    func exp2(x: f32) => Swag.exp2(x)
    func exp2(x: f64) => Swag.exp2(x)

    // Returns `x` raised to the power `y`.
    func pow(x, y: f32) => Swag.pow(x, y)
    func pow(x, y: f64) => Swag.pow(x, y)

    // Returns `x * y + z`.
    func mulAdd(x, y, z: f32) => Swag.muladd(x, y, z)
    func mulAdd(x, y, z: f64) => Swag.muladd(x, y, z)
}
