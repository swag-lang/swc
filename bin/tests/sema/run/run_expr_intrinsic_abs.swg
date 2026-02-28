#global fileprivate

#test
{
    #[Swag.NoInline]
    func absRuntimeS8(v: s8)->s8 => @abs(v)
    #[Swag.NoInline]
    func absRuntimeS16(v: s16)->s16 => @abs(v)
    #[Swag.NoInline]
    func absRuntimeS32(v: s32)->s32 => @abs(v)
    #[Swag.NoInline]
    func absRuntimeS64(v: s64)->s64 => @abs(v)

    #[Swag.NoInline]
    func absRuntimeF32(v: f32)->f32 => @abs(v)
    #[Swag.NoInline]
    func absRuntimeF64(v: f64)->f64 => @abs(v)

    const S8  = #run absRuntimeS8(-7's8)
    const S16 = #run absRuntimeS16(-321's16)
    const S32 = #run absRuntimeS32(-123456)
    const S64 = #run absRuntimeS64(-5000000000's64)
    const F32 = #run absRuntimeF32(-3.5'f32)
    const F64 = #run absRuntimeF64(-9.25)

    #assert(S8 == 7)
    #assert(S16 == 321)
    #assert(S32 == 123456)
    #assert(S64 == 5000000000)
    #assert(F32 == 3.5)
    #assert(F64 == 9.25)
}
