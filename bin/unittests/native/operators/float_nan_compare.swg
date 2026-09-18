#global private
#global #[Swag.Safety(.All, false)]

func eqF32(a: f32, b: f32)->bool
{
    return a == b
}

func neF32(a: f32, b: f32)->bool
{
    return a != b
}

func ltF32(a: f32, b: f32)->bool
{
    return a < b
}

func leF32(a: f32, b: f32)->bool
{
    return a <= b
}

func gtF32(a: f32, b: f32)->bool
{
    return a > b
}

func geF32(a: f32, b: f32)->bool
{
    return a >= b
}

func cmpF32(a: f32, b: f32)->s32
{
    return a <=> b
}

func eqF64(a: f64, b: f64)->bool
{
    return a == b
}

func neF64(a: f64, b: f64)->bool
{
    return a != b
}

func ltF64(a: f64, b: f64)->bool
{
    return a < b
}

func leF64(a: f64, b: f64)->bool
{
    return a <= b
}

func gtF64(a: f64, b: f64)->bool
{
    return a > b
}

func geF64(a: f64, b: f64)->bool
{
    return a >= b
}

func cmpF64(a: f64, b: f64)->s32
{
    return a <=> b
}

func switchNaNEquality()->bool
{
    let value = Swag.F32.NaN
    switch value
    {
    case Swag.F32.NaN:
        return false
    default:
        return true
    }
}

func switchNaNRange()->bool
{
    let value = Swag.F64.NaN
    switch value
    {
    case to 10.0'f64:
        return false
    default:
        return true
    }
}

// Finite f32 comparisons stay at their source width.
#test
{
    const a = 1.25'f32
    const b = 2.5'f32

    Swag.assert(not eqF32(a, b))
    Swag.assert(eqF32(a, a))
    Swag.assert(neF32(a, b))
    Swag.assert(ltF32(a, b))
    Swag.assert(leF32(a, b))
    Swag.assert(not gtF32(a, b))
    Swag.assert(not geF32(a, b))
    Swag.assert(cmpF32(a, b) == -1)
    Swag.assert(cmpF32(b, a) == 1)
    Swag.assert(cmpF32(a, a) == 0)
}

// NaN comparison for f32
#test
{
    const a = Swag.F32.NaN
    const b = Swag.F32.NaN

    Swag.assert(not eqF32(a, b))
    Swag.assert(neF32(a, b))
    Swag.assert(not ltF32(a, b))
    Swag.assert(not leF32(a, b))
    Swag.assert(not gtF32(a, b))
    Swag.assert(not geF32(a, b))
    Swag.assert(cmpF32(a, b) == 0)
}

// NaN comparison for f64
#test
{
    const a = Swag.F64.NaN
    const b = Swag.F64.NaN

    Swag.assert(not eqF64(a, b))
    Swag.assert(neF64(a, b))
    Swag.assert(not ltF64(a, b))
    Swag.assert(not leF64(a, b))
    Swag.assert(not gtF64(a, b))
    Swag.assert(not geF64(a, b))
    Swag.assert(cmpF64(a, b) == 0)
}

// NaN in switch equality and range
#test
{
    Swag.assert(switchNaNEquality())
    Swag.assert(switchNaNRange())
}
