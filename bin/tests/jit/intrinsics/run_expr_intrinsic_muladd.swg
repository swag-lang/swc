#global fileprivate

#test
{
    #[Swag.NoInline]
    func mulAddF32(a, b, c: f32)->f32 => @muladd(a, b, c)
    #[Swag.NoInline]
    func mulAddF64(a, b, c: f64)->f64 => @muladd(a, b, c)

    const A = #run mulAddF32(2.5'f32, 4.0'f32, -1.0'f32)
    const B = #run mulAddF64(3.0, 7.0, 5.0)
    const C = #run mulAddF32(-2.0'f32, -8.0'f32, 0.5'f32)
    const D = #run mulAddF64(-6.0, 2.0, 1.25)

    #assert(A == 9.0)
    #assert(B == 26.0)
    #assert(C == 16.5)
    #assert(D == -10.75)
}
