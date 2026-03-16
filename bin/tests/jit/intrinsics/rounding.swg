#global fileprivate // swc-option suite-jit

#test
{
    #[Swag.NoInline]
    func floorF32(v: f32)->f32 => @floor(v)
    #[Swag.NoInline]
    func ceilF32(v: f32)->f32 => @ceil(v)
    #[Swag.NoInline]
    func truncF32(v: f32)->f32 => @trunc(v)
    #[Swag.NoInline]
    func roundF32(v: f32)->f32 => @round(v)

    #[Swag.NoInline]
    func floorF64(v: f64)->f64 => @floor(v)
    #[Swag.NoInline]
    func ceilF64(v: f64)->f64 => @ceil(v)
    #[Swag.NoInline]
    func truncF64(v: f64)->f64 => @trunc(v)
    #[Swag.NoInline]
    func roundF64(v: f64)->f64 => @round(v)

    const A0 = #run floorF32(1.75'f32)
    const A1 = #run floorF64(-1.1)
    const B0 = #run ceilF32(1.1'f32)
    const B1 = #run ceilF64(-1.75)
    const C0 = #run truncF32(-1.75'f32)
    const C1 = #run truncF64(1.75)
    const D0 = #run roundF32(1.5'f32)
    const D1 = #run roundF32(-1.5'f32)
    const D2 = #run roundF64(2.5)
    const D3 = #run roundF64(-2.5)

    #assert(A0 == 1.0)
    #assert(A1 == -2.0)
    #assert(B0 == 2.0)
    #assert(B1 == -1.0)
    #assert(C0 == -1.0)
    #assert(C1 == 1.0)
    #assert(D0 == 2.0)
    #assert(D1 == -2.0)
    #assert(D2 == 3.0)
    #assert(D3 == -3.0)
}
