#global private

// A struct-literal field written with a NAMED argument and a constant value, converted to
// the field type through an implicit 'opSet' that is not '#[Swag.ConstExpr]'. The named
// argument copies its value's payload when it resolves, which is before the literal casts
// that value to the field type; the constant it kept then made code generation emit the
// argument as a constant and skip its children, so the conversion was never lowered and
// the field read uninitialized storage. A positional field and a runtime source both take
// the same conversion and must agree with the named constant one.
struct Radians
{
    value: f32 = -1
}

impl Radians
{
    #[Swag.Implicit]
    mtd opSet(v: f32)
    {
        .value = v + 100
    }
}

struct InlineRadians
{
    value: f32 = -1
}

impl InlineRadians
{
    #[Swag.Implicit, Swag.Inline]
    mtd opSet(v: f32)
    {
        .value = v + 100
    }
}

struct Shape
{
    sides: s32 = 3
    angle: Radians
}

struct InlineShape
{
    sides: s32 = 3
    angle: InlineRadians
}

#test
{
    let named = Shape{sides: 5, angle: 1.5}
    Swag.assert(named.sides == 5)
    Swag.assert(named.angle.value == 101.5)
}

#test
{
    let positional = Shape{5, 1.5}
    Swag.assert(positional.sides == 5)
    Swag.assert(positional.angle.value == 101.5)
}

#test
{
    var source: f32 = 1.5
    let runtime     = Shape{sides: 5, angle: source}
    Swag.assert(runtime.angle.value == 101.5)
}

#test
{
    let inlined = InlineShape{sides: 5, angle: 1.5}
    Swag.assert(inlined.angle.value == 101.5)
}

#test
{
    // The same conversion outside a literal, as the control the named form must match.
    let direct: Radians = 1.5
    Swag.assert(direct.value == 101.5)
}
