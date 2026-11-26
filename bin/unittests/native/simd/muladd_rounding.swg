// Packed mulAdd rounds the product before addition, as the scalar intrinsic does.
#[Swag.NoInline]
func multiplyAddPacked32(a, b, c: #simd [4] f32)->#simd [4] f32 => Swag.mulAdd(a, b, c)

#[Swag.NoInline]
func multiplyAddPacked64(a, b, c: #simd [2] f64)->#simd [2] f64 => Swag.mulAdd(a, b, c)

#test
{
    let a      = Swag.vecSplat(1.0001220703125_f32)
    let b      = Swag.vecSplat(0.9998779296875_f32)
    let c      = Swag.vecSplat(-1.0_f32)
    let result = cast([4] f32, multiplyAddPacked32(a, b, c))
    for lane in result
    {
        Swag.require(lane == 0)
    }
}

#test
{
    let a      = Swag.vecSplat(1.000000007450580596923828125_f64)
    let b      = Swag.vecSplat(0.999999992549419403076171875_f64)
    let c      = Swag.vecSplat(-1.0_f64)
    let result = cast([2] f64, multiplyAddPacked64(a, b, c))
    for lane in result
    {
        Swag.require(lane == 0)
    }
}
