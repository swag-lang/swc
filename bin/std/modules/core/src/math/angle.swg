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
}
