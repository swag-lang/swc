#global private

// `d < c and d > -c` becomes one test of |d|. NaN, signed zeros, infinities,
// subnormals and the bounds themselves must answer as the two tests do, for
// f32 and f64, strict and not.

#[Swag.Optimize(true), Swag.NoInline]
func nearF32(d: f32)->bool => d < 0.001 and d > -0.001
#[Swag.Optimize(false), Swag.NoInline]
func nearF32Ref(d: f32)->bool => d < 0.001 and d > -0.001

#[Swag.Optimize(true), Swag.NoInline]
func withinF32(d: f32)->bool => d <= 2.5 and d >= -2.5
#[Swag.Optimize(false), Swag.NoInline]
func withinF32Ref(d: f32)->bool => d <= 2.5 and d >= -2.5

#[Swag.Optimize(true), Swag.NoInline]
func nearF64(d: f64)->bool => d < 1e-9 and d > -1e-9
#[Swag.Optimize(false), Swag.NoInline]
func nearF64Ref(d: f64)->bool => d < 1e-9 and d > -1e-9

#test
{
    let nan     = cast #bit (f32) 0x7FC00000'u32
    let negZero = cast #bit (f32) 0x80000000'u32
    let inf     = cast #bit (f32) 0x7F800000'u32
    let tiny    = cast #bit (f32) 0x00000001'u32
    let values: [14] f32 = [0.0, negZero, 0.001, -0.001, 0.0009, -0.0009, 2.5, -2.5, 2.4999, -2.5001, nan, inf, -inf, tiny]
    for v in values
    {
        Swag.assert(nearF32(v) == nearF32Ref(v))
        Swag.assert(withinF32(v) == withinF32Ref(v))
        let w = cast(f64) v
        Swag.assert(nearF64(w) == nearF64Ref(w))
        Swag.assert(nearF64(w * 1e-7) == nearF64Ref(w * 1e-7))
    }
}
