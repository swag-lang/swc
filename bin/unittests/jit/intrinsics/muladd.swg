#global private

#test
{
    #[Swag.NoInline]
    func mulAddF32(a, b, c: f32)->f32 => Swag.mulAdd(a, b, c)
    #[Swag.NoInline]
    func mulAddF64(a, b, c: f64)->f64 => Swag.mulAdd(a, b, c)

    const A = #run mulAddF32(2.5_f32, 4.0_f32, -1.0_f32)
    const B = #run mulAddF64(3.0, 7.0, 5.0)
    const C = #run mulAddF32(-2.0_f32, -8.0_f32, 0.5_f32)
    const D = #run mulAddF64(-6.0, 2.0, 1.25)

    #assert(A == 9.0)
    #assert(B == 26.0)
    #assert(C == 16.5)
    #assert(D == -10.75)
}
