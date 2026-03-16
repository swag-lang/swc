#global fileprivate // swc-option suite-jit

#test
{
    #[Swag.NoInline]
    func sqrtRuntimeF64(v: f64)->f64
    {
        return @sqrt(v)
    }

    #[Swag.NoInline]
    func sqrtRuntimeF32(v: f32)->s32
    {
        return cast(s32) @sqrt(v)
    }

    const R0 = #run sqrtRuntimeF64(9.0)
    const R1 = #run sqrtRuntimeF32(16.0'f32)
    #assert(R0 == 3.0)
    #assert(R1 == 4)
}
