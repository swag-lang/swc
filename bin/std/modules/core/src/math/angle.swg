#global public
#global namespace Math

using Swag

// Represents an angle stored in radians.
struct Angle
{
    readonly radians: f32     // The angle value in radians.
}

impl Angle
{
    // Assign a radian value directly to the angle.
    // Allows implicit conversion from floating-point values representing radians.
    #[ConstExpr, Implicit, Inline]
    mtd opSet(valueRadians: f32)
    {
        .radians = valueRadians
    }

    // Assign angle values with unit suffixes (rad or deg).
    // Supports literal syntax like '90'deg' or '1.57'rad' for convenient angle creation.
    #[ConstExpr, Implicit, Inline]
    mtd(suffix: string) opSetLiteral(value: f32)
    {
        #static switch suffix
        {
        case "rad": .radians = value
        case "deg": .radians = Math.toRadians(value)
        default:    #error("invalid angle literal suffix [[" ++ suffix ++ "]]")
        }
    }

    // Creates an angle from a value in radians.
    #[ConstExpr, Inline]
    func fromRadians(value: f32)->Angle => {radians: value}

    // Creates an angle from a value in degrees.
    #[ConstExpr, Inline]
    func fromDegrees(value: f32)->Angle => {radians: Math.toRadians(value)}

    // Convert the angle from radians to degrees.
    // Returns the angle value in degrees as a floating-point number.
    #[Inline]
    mtd const toDegrees()->f32 => Math.toDegrees(.radians)
}
