// Multiplication rounds to the declared width before addition, at compile time and at runtime.
#[Swag.NoInline]
func multiplyAdd64(a, b, c: f64)->f64 => Swag.mulAdd(a, b, c)

#[Swag.NoInline]
func multiplyAdd32(a, b, c: f32)->f32 => Swag.mulAdd(a, b, c)

#test
{
    const A      = 1.000000007450580596923828125_f64
    const B      = 0.999999992549419403076171875_f64
    const Folded = Swag.mulAdd(A, B, -1.0_f64)
    Swag.require(Folded == 0.0)
    Swag.require(multiplyAdd64(A, B, -1.0) == Folded)
}

#test
{
    const A      = 1.0001220703125_f32
    const B      = 0.9998779296875_f32
    const Folded = Swag.mulAdd(A, B, -1.0_f32)
    Swag.require(Folded == 0.0)
    Swag.require(multiplyAdd32(A, B, -1.0) == Folded)
}
