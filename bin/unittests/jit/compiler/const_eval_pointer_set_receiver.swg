#global private

// Compile-time folding of an implicit 'opSet' conversion: the receiver parameter is a
// non-null value pointer, so the const-set fold must build the receiver home and pass its
// address, exactly as it did for a reference receiver. Declined, the aggregate-literal
// field falls back to a runtime path and loses the constant source.
struct Angle
{
    radians: f32
}

impl Angle
{
    #[Swag.ConstExpr, Swag.Implicit, Swag.Inline]
    mtd opSet(valueRadians: f32)
    {
        .radians = valueRadians
    }

    #[Swag.ConstExpr, Swag.Implicit, Swag.Inline]
    mtd(suffix: string) opSetLiteral(value: f32)
    {
        #static switch suffix
        {
        case "rad": .radians = value
        case "deg": .radians = value * 2.0
        default:    #error("invalid angle literal suffix")
        }
    }
}

struct Holder
{
    angle: Angle
}

#test
{
    // Suffixed literal on a plain variable.
    let direct: Angle = 10.0'deg
    Swag.assert(direct.radians == 20.0)
}

#test
{
    // Suffixed literal on a struct literal field.
    let holder = Holder{angle: 10.0'deg}
    Swag.assert(holder.angle.radians == 20.0)
}

#test
{
    // Plain implicit opSet on a struct literal field, let and var destinations.
    let a = Holder{angle: 1.5}
    Swag.assert(a.angle.radians == 1.5)
    var b = Holder{angle: 2.5}
    Swag.assert(b.angle.radians == 2.5)
}
