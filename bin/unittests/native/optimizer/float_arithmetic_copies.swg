#global private

// Keep every input alive after the independent arithmetic results, including
// the arguments passed on the stack rather than in floating-point registers.
#[Swag.NoInline]
func independentFloat64(a, b, c, d, e, f, g, h: f64)->f64
{
    let first = (a + b) * (c - d) + e / f - g * h
    return first + a + b + c + d + e + f + g + h
}

#[Swag.NoInline]
func independentFloat32(a, b, c, d, e, f, g, h: f32)->f32
{
    let first = (a + b) * (c - d) + e / f - g * h
    return first + a + b + c + d + e + f + g + h
}

#test
{
    Swag.assert(independentFloat64(1.5, 2.5, 8, 4, 16, 2, 3, 0.5) == 60)
    Swag.assert(independentFloat32(1.5, 2.5, 8, 4, 16, 2, 3, 0.5) == 60)
    Swag.assert(independentFloat64(2, 2, 2, 2, 2, 2, 2, 2) == 13)
    Swag.assert(independentFloat32(2, 2, 2, 2, 2, 2, 2, 2) == 13)
}
