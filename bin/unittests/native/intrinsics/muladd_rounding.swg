// Multiplication rounds to the declared width before addition, at compile time and at runtime.
#[Swag.NoInline]
func multiplyAdd64(a, b, c: f64)->f64 => Swag.muladd(a, b, c)

#[Swag.NoInline]
func multiplyAdd32(a, b, c: f32)->f32 => Swag.muladd(a, b, c)

#test
{
    const A      = 1.000000007450580596923828125'f64
    const B      = 0.999999992549419403076171875'f64
    const Folded = Swag.muladd(A, B, -1.0'f64)
    Swag.assert(Folded == 0.0)
    Swag.assert(multiplyAdd64(A, B, -1.0) == Folded)
}

#test
{
    const A      = 1.0001220703125'f32
    const B      = 0.9998779296875'f32
    const Folded = Swag.muladd(A, B, -1.0'f32)
    Swag.assert(Folded == 0.0)
    Swag.assert(multiplyAdd32(A, B, -1.0) == Folded)
}
