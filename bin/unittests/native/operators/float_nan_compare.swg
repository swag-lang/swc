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

// NaN comparison for f32
#test
{
    const a = Swag.F32.NaN
    const b = Swag.F32.NaN

    Swag.assert(!eqF32(a, b))
    Swag.assert(neF32(a, b))
    Swag.assert(!ltF32(a, b))
    Swag.assert(!leF32(a, b))
    Swag.assert(!gtF32(a, b))
    Swag.assert(!geF32(a, b))
    Swag.assert(cmpF32(a, b) == 0)
}

// NaN comparison for f64
#test
{
    const a = Swag.F64.NaN
    const b = Swag.F64.NaN

    Swag.assert(!eqF64(a, b))
    Swag.assert(neF64(a, b))
    Swag.assert(!ltF64(a, b))
    Swag.assert(!leF64(a, b))
    Swag.assert(!gtF64(a, b))
    Swag.assert(!geF64(a, b))
    Swag.assert(cmpF64(a, b) == 0)
}

// NaN in switch equality and range
#test
{
    Swag.assert(switchNaNEquality())
    Swag.assert(switchNaNRange())
}
