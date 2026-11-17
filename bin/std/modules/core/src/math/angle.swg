#global public
#global namespace Math

using Swag

// Stores an angle in radians.
//
// An `f32` converts to an angle as radians, and a literal can name its unit instead, as in
// `90'deg` or `1.57'rad`.
struct Angle
{
    public readonly radians: f32     // The angle value in radians.
}

impl Angle
{
    // Sets the angle from `valueRadians`, in radians.
    //
    // This is what lets an `f32` initialize or assign an angle directly.
    #[ConstExpr, Implicit, Inline]
    mtd opSet(valueRadians: f32)
    {
        .radians = valueRadians
    }

    // Sets the angle from a literal whose suffix, `rad` or `deg`, names its unit.
    //
    // This is what lets `90'deg` and `1.57'rad` initialize an angle. Any other suffix is rejected
    // at compile time.
    #[ConstExpr, Implicit, Inline]
    mtd(suffix: string) opSetLiteral(value: f32)
    {
        #static switch suffix
        {
        case "rad": .radians = value
        case "deg": .radians = Math.toRadians(value)
        default:    #error("invalid angle literal suffix [[", suffix, "]]")
        }
    }

    // Creates an angle from a value in radians.
    #[ConstExpr, Inline]
    func fromRadians(value: f32)->Angle => {radians: value}

    // Creates an angle from a value in degrees.
    #[ConstExpr, Inline]
    func fromDegrees(value: f32)->Angle => {radians: Math.toRadians(value)}

    // Returns the angle in degrees.
    #[Inline]
    mtd const toDegrees()->f32 => Math.toDegrees(.radians)

    // Adds or subtracts another angle, preserving radians as the stored unit.
    #[Inline]
    mtd(op: Swag.Operator) const opBinary(other: Angle)->Angle
        where op == .Add or op == .Sub
    {
        #static switch op
        {
        case .Add: return Angle.fromRadians(.radians + other.radians)
        case .Sub: return Angle.fromRadians(.radians - other.radians)
        }
    }

    // Reverses the direction of this angle.
    #[Inline]
    mtd(op: Swag.Operator) const opUnary()->Angle
        where op == .Neg
    {
        return Angle.fromRadians(-.radians)
    }

    // Scales this angle by `factor`.
    #[Inline, Swag.Commutative(.Mul)]
    mtd(op: Swag.Operator) const opBinary(factor: f32)->Angle
        where op == .Mul or op == .Div
    {
        #static switch op
        {
        case .Mul: return Angle.fromRadians(.radians * factor)
        case .Div: return Angle.fromRadians(.radians / factor)
        }
    }

    // Applies angle addition, subtraction, or scalar multiplication and division in place.
    #[Inline]
    mtd(op: Swag.Operator) opAssign(value: Angle)
        where op == .AddAssign or op == .SubAssign
    {
        #static switch op
        {
        case .AddAssign: .radians += value.radians
        case .SubAssign: .radians -= value.radians
        }
    }

    #[Inline]
    mtd(op: Swag.Operator) opAssign(factor: f32)
        where op == .MulAssign or op == .DivAssign
    {
        #static switch op
        {
        case .MulAssign: .radians *= factor
        case .DivAssign: .radians /= factor
        }
    }

    // Returns the same direction normalized to [0, 2π).
    #[Inline]
    mtd const normalized()->Angle => Angle.fromRadians(Math.wrap(.radians, 0'f32, Math.ConstF32.TwoPi))

    // Returns the same direction normalized to [-π, π).
    #[Inline]
    mtd const normalizedSigned()->Angle => Angle.fromRadians(Math.wrap(.radians + Math.ConstF32.Pi, 0'f32, Math.ConstF32.TwoPi) - Math.ConstF32.Pi)

    // Returns the signed shortest turn from this angle to `other`, in [-π, π).
    #[Inline]
    mtd const deltaTo(other: Angle)->Angle => Angle.fromRadians(Math.deltaAngle(.radians, other.radians))

    // Interpolates toward `other` along the shortest angular path.
    //
    // `factor` is not clamped. The result is not normalized, so extrapolation stays continuous.
    #[Inline]
    mtd const lerpTo(other: Angle, factor: f32)->Angle
        => Angle.fromRadians(Math.lerpAngle(.radians, other.radians, factor))

    // Returns the sine of this angle.
    #[Inline]
    mtd const sin()->f32 => Math.sin(.radians)

    // Returns the cosine of this angle.
    #[Inline]
    mtd const cos()->f32 => Math.cos(.radians)
}
