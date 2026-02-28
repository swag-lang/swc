#global fileprivate

#test
{
    #[Swag.NoInline]
    func minRuntimeS32(a: s32, b: s32)->s32
    {
        return @min(a, b)
    }

    #[Swag.NoInline]
    func maxRuntimeS32(a: s32, b: s32)->s32
    {
        return @max(a, b)
    }

    #[Swag.NoInline]
    func minRuntimeU64(a: u64, b: u64)->u64
    {
        return @min(a, b)
    }

    #[Swag.NoInline]
    func maxRuntimeU64(a: u64, b: u64)->u64
    {
        return @max(a, b)
    }

    #[Swag.NoInline]
    func minRuntimeF64(a: f64, b: f64)->f64
    {
        return @min(a, b)
    }

    #[Swag.NoInline]
    func maxRuntimeF32(a: f32, b: f32)->f32
    {
        return @max(a, b)
    }

    const A0 = #run minRuntimeS32(-7, 3)
    const A1 = #run maxRuntimeS32(-7, 3)
    const B0 = #run minRuntimeU64(4'u64, 9'u64)
    const B1 = #run maxRuntimeU64(4'u64, 9'u64)
    const C0 = #run minRuntimeF64(6.5, 3.0)
    const C1 = #run maxRuntimeF32(1.25'f32, 2.75'f32)

    #assert(A0 == -7)
    #assert(A1 == 3)
    #assert(B0 == 4)
    #assert(B1 == 9)
    #assert(C0 == 3.0)
    #assert(C1 == 2.75)
}
