#global public
#global namespace Math

// Structure containing mathematical constants of type 'T'
struct(T) Const
{
    const Pi:         T = 3.1415927410125732421875     // Pi constant
    const E:          T = 2.71828174591064453125       // Euler's number
    const TwoPi:      T = 2 * Pi                       // 2 times Pi
    const PiBy2:      T = Pi / 2                       // Pi divided by 2
    const PiBy3:      T = Pi / 3                       // Pi divided by 3
    const PiBy4:      T = Pi / 4                       // Pi divided by 4
    const PiBy6:      T = Pi / 6                       // Pi divided by 6
    const PiBy8:      T = Pi / 8                       // Pi divided by 8
    const ThreePiBy4: T = 3 * Pi / 4                   // 3 times Pi divided by 4
    const OneByPi:    T = 1 / Pi                       // Reciprocal of Pi
    const TwoByPi:    T = 2 / Pi                       // 2 divided by Pi
    const Sqrt2:      T = sqrt(cast(T) 2)              // Square root of 2
    const OneBySqrt2: T = 1 / Sqrt2                    // Reciprocal of square root of 2
    const Ln2:        T = log(cast(T) 2)               // Natural logarithm of 2
    const Ln10:       T = log(cast(T) 10)              // Natural logarithm of 10
    const Log2E:      T = log2(E)                      // Log base 2 of Euler's number
    const Log10E:     T = log10(E)                     // Log base 10 of Euler's number
    const Epsilon:    T = 1e-06                        // Smallest value for floating-point precision comparisons
}

// Aliases for 32-bit and 64-bit floating-point constants
alias ConstF32 = Const'f32

// Names the const f64 type.
alias ConstF64 = Const'f64

#[Swag.ConstExpr, Swag.Inline]
{
    // Returns the sign of 'x' (-1 for negative, 0 for zero, and 1 for positive).
    func sign(x: f32) => cast(f32) (x > 0) - cast(f32) (x < 0)
    func sign(x: f64) => cast(f64) (x > 0) - cast(f64) (x < 0)

    // Clamps 'x' between 0 and 1
    func saturate(x: f32) => clamp(x, 0'f32, 1'f32)
    func saturate(x: f64) => clamp(x, 0'f64, 1'f64)

    // Linear interpolation between 'x' and 'y' based on 'factor'
    func lerp(x, y, factor: f32) => x + factor * (y - x)
    func lerp(x, y, factor: f64) => x + factor * (y - x)

    // Cubic interpolation between 'a', 'b', 'c', and 'd' based on 't'
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

    // Hermite interpolation function
    func interpHermite(t: f32) => t * t * (3 - 2 * t)
    func interpHermite(t: f64) => t * t * (3 - 2 * t)

    // Quintic interpolation function
    func interpQuintic(t: f32) => t * t * t * (t * (t * 6 - 15) + 10)
    func interpQuintic(t: f64) => t * t * t * (t * (t * 6 - 15) + 10)

    // Get the fractional part
    func fract(x: f32)->f32 => x - floor(x)
    func fract(x: f64)->f64 => x - floor(x)

    // Interpolation at constant speed - moves a fixed distance per step
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

    // Perform smooth damping interpolation towards 'target'.
    // Uses 'smoothTime' and 'deltaTime' for frame-rate independent smooth movement.
    // 'currentVelocity' is modified to track the current rate of change.
    // Based on Game Programming Gems 4 Chapter 1.10
    func(T) smoothDamp(current, target: T, currentVelocity: *T, smoothTime, deltaTime: T)->T
    {
        // Clamp smoothTime to prevent division by zero and ensure stability
        let smoothTimeActual = Math.max(0.0001, smoothTime)

        // Calculate the omega (frequency) and zeta (damping coefficient)
        let omega = 2.0 / smoothTimeActual
        let x     = omega * deltaTime
        let exp   = 1.0 / (1.0 + x + 0.48 * x * x + 0.235 * x * x * x)

        // Calculate change and target offset
        let change     = current - target
        let originalTo = target

        // Clamp maximum change (optional speed limit)
        #static if T == f32 do
            let maxChange = Swag.F32.Max * smoothTimeActual
        else do
            let maxChange = Swag.F64.Max * smoothTimeActual
        let clampedChange = Math.clamp(change, -maxChange, maxChange)
        let newTarget     = current - clampedChange

        // Calculate new velocity and position
        let currentVelocityValue = dref currentVelocity
        let temp                 = (currentVelocityValue + omega * clampedChange) * deltaTime
        dref currentVelocity = (currentVelocityValue - omega * temp) * exp
        var result = newTarget + (clampedChange + temp) * exp

        // Prevent overshooting
        if (originalTo - current > 0.0) == (result > originalTo)
        {
            result               = originalTo
            dref currentVelocity = (result - originalTo) / deltaTime
        }

        return result
    }

    // Convert radians to degrees
    func toDegrees(x: f32) => x * 57.295779513082320876798154814105'f32

    // Converts degrees to radians.
    func toRadians(x: f32) => x * 0.017453292519943295769236907684886'f32
    func toDegrees(x: f64) => x * (180'f64 / ConstF64.Pi)

    // Converts this value to radians.
    func toRadians(x: f64) => x * (ConstF64.Pi / 180'f64)

    // Check if 'x' is approximately zero within an epsilon threshold
    func isZeroEpsilon(x: f32, eps = ConstF32.Epsilon) => abs(x) < eps
    func isZeroEpsilon(x: f64, eps = ConstF64.Epsilon) => abs(x) < eps

    // Check if 'x' and 'y' are approximately equal within an epsilon threshold
    func isEqualEpsilon(x, y: f32, eps = ConstF32.Epsilon) => abs(x - y) < eps
    func isEqualEpsilon(x, y: f64, eps = ConstF64.Epsilon) => abs(x - y) < eps

    // Check if 'x' is NaN (not a number)
    #[Swag.Safety(.NaN, false)]
    func isNaN(x: f32) => x != x
    #[Swag.Safety(.NaN, false)]
    func isNaN(x: f64) => x != x

    // Returns true if the value is finite (not infinite and not NaN).
    // A finite number is any real number that is not positive infinity, negative infinity, or NaN.
    func isFinite(value: f32)->bool
    {
        let bits = cast #bit (u32) value
        return (bits & 0x7F800000'u32) != 0x7F800000'u32
    }

    // Returns true if the value is finite (not infinite and not NaN).
    // A finite number is any real number that is not positive infinity, negative infinity, or NaN.
    func isFinite(value: f64)->bool
    {
        let bits = cast #bit (u64) value
        return (bits & 0x7FF0000000000000'u64) != 0x7FF0000000000000'u64
    }

    // Smoothstep interpolation between 'edge0' and 'edge1'
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

    // Maps 'val' from the range [minSrc, maxSrc] to [minDst, maxDst]
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

    // Returns the smallest power of ten strictly greater than 'value'.
    func nextPowerOfTen(value: f32)->f32
    {
        if value < 1 do
            return 1'f32
        return pow(10'f32, floor(log10(value)) + 1)
    }

    // Returns the smallest power of ten strictly greater than 'value'.
    func nextPowerOfTen(value: f64)->f64
    {
        if value < 1 do
            return 1'f64
        return pow(10'f64, floor(log10(value)) + 1)
    }
}

#[Swag.ConstExpr, Swag.Inline]
{
    // Returns the signed arc tangent of the coordinates 'y' and 'x'.
    func atan2(y, x: f32) => @atan2(y, x)

    // Returns the signed arc tangent of the coordinates 'y' and 'x'.
    func atan2(y, x: f64) => @atan2(y, x)

    // Performs the sqrt operation.
    func sqrt(x: f32) => @sqrt(x)

    // Returns the square root.
    func sqrt(x: f64) => @sqrt(x)

    // Performs the sin operation.
    func sin(x: f32) => @sin(x)

    // Returns the sine of an angle in radians.
    func sin(x: f64) => @sin(x)

    // Performs the cos operation.
    func cos(x: f32) => @cos(x)

    // Returns the cosine of an angle in radians.
    func cos(x: f64) => @cos(x)

    // Performs the tan operation.
    func tan(x: f32) => @tan(x)

    // Returns the tangent of an angle in radians.
    func tan(x: f64) => @tan(x)

    // Performs the sinh operation.
    func sinh(x: f32) => @sinh(x)

    // Returns the hyperbolic sine.
    func sinh(x: f64) => @sinh(x)

    // Performs the cosh operation.
    func cosh(x: f32) => @cosh(x)

    // Returns the hyperbolic cosine.
    func cosh(x: f64) => @cosh(x)

    // Performs the tanh operation.
    func tanh(x: f32) => @tanh(x)

    // Returns the hyperbolic tangent.
    func tanh(x: f64) => @tanh(x)

    // Performs the asin operation.
    func asin(x: f32) => @asin(x)

    // Returns the arc sine in radians.
    func asin(x: f64) => @asin(x)

    // Performs the acos operation.
    func acos(x: f32) => @acos(x)

    // Returns the arc cosine in radians.
    func acos(x: f64) => @acos(x)

    // Performs the atan operation.
    func atan(x: f32) => @atan(x)

    // Returns the arc tangent in radians.
    func atan(x: f64) => @atan(x)

    // Performs the log operation.
    func log(x: f32) => @log(x)

    // Returns the natural logarithm.
    func log(x: f64) => @log(x)

    // Performs the log2 operation.
    func log2(x: f32) => @log2(x)

    // Returns the base-two logarithm.
    func log2(x: f64) => @log2(x)

    // Performs the log10 operation.
    func log10(x: f32) => @log10(x)

    // Returns the base-ten logarithm.
    func log10(x: f64) => @log10(x)

    // Performs the floor operation.
    func floor(x: f32) => @floor(x)

    // Rounds downward to an integer-valued number.
    func floor(x: f64) => @floor(x)

    // Performs the ceil operation.
    func ceil(x: f32) => @ceil(x)

    // Rounds upward to an integer-valued number.
    func ceil(x: f64) => @ceil(x)

    // Performs the trunc operation.
    func trunc(x: f32) => @trunc(x)

    // Removes the fractional part.
    func trunc(x: f64) => @trunc(x)

    // Performs the round operation.
    func round(x: f32) => @round(x)

    // Rounds to the nearest integer-valued number.
    func round(x: f64) => @round(x)

    // Performs the floor s32 operation.
    func floorS32(x: f32) => cast(s32) @floor(x)

    // Performs the floor s64 operation.
    func floorS64(x: f64) => cast(s64) @floor(x)

    // Performs the ceil s32 operation.
    func ceilS32(x: f32) => cast(s32) @ceil(x)

    // Performs the ceil s64 operation.
    func ceilS64(x: f64) => cast(s64) @ceil(x)

    // Performs the trunc s32 operation.
    func truncS32(x: f32) => cast(s32) @trunc(x)

    // Performs the trunc s64 operation.
    func truncS64(x: f64) => cast(s64) @trunc(x)

    // Performs the round s32 operation.
    func roundS32(x: f32) => cast(s32) @round(x)

    // Performs the round s64 operation.
    func roundS64(x: f64) => cast(s64) @round(x)

    // Performs the abs operation.
    func abs(x: f32) => @abs(x)

    // Returns the absolute value.
    func abs(x: f64) => @abs(x)

    // Performs the min operation.
    func min(x, y: f32) => @min(x, y)

    // Returns the lesser value.
    func min(x, y: f64) => @min(x, y)

    // Performs the max operation.
    func max(x, y: f32) => @max(x, y)

    // Returns the greater value.
    func max(x, y: f64) => @max(x, y)

    // Performs the exp operation.
    func exp(x: f32) => @exp(x)

    // Raises Euler's number to the requested power.
    func exp(x: f64) => @exp(x)

    // Performs the exp2 operation.
    func exp2(x: f32) => @exp2(x)

    // Raises two to the requested power.
    func exp2(x: f64) => @exp2(x)

    // Performs the pow operation.
    func pow(x, y: f32) => @pow(x, y)

    // Raises a value to a power.
    func pow(x, y: f64) => @pow(x, y)

    // Performs the mul add operation.
    func mulAdd(x, y, z: f32) => @muladd(x, y, z)

    // Multiplies two values and adds a third.
    func mulAdd(x, y, z: f64) => @muladd(x, y, z)
}
