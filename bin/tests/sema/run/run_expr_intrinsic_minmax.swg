#global fileprivate

#test
{
    #[Swag.NoInline]
    func minRuntimeS8(a: s8, b: s8)->s8 => @min(a, b)
    #[Swag.NoInline]
    func maxRuntimeS8(a: s8, b: s8)->s8 => @max(a, b)
    #[Swag.NoInline]
    func minRuntimeS16(a: s16, b: s16)->s16 => @min(a, b)
    #[Swag.NoInline]
    func maxRuntimeS16(a: s16, b: s16)->s16 => @max(a, b)
    #[Swag.NoInline]
    func minRuntimeS32(a: s32, b: s32)->s32 => @min(a, b)
    #[Swag.NoInline]
    func maxRuntimeS32(a: s32, b: s32)->s32 => @max(a, b)
    #[Swag.NoInline]
    func minRuntimeS64(a: s64, b: s64)->s64 => @min(a, b)
    #[Swag.NoInline]
    func maxRuntimeS64(a: s64, b: s64)->s64 => @max(a, b)

    #[Swag.NoInline]
    func minRuntimeU8(a: u8, b: u8)->u8 => @min(a, b)
    #[Swag.NoInline]
    func maxRuntimeU8(a: u8, b: u8)->u8 => @max(a, b)
    #[Swag.NoInline]
    func minRuntimeU16(a: u16, b: u16)->u16 => @min(a, b)
    #[Swag.NoInline]
    func maxRuntimeU16(a: u16, b: u16)->u16 => @max(a, b)
    #[Swag.NoInline]
    func minRuntimeU32(a: u32, b: u32)->u32 => @min(a, b)
    #[Swag.NoInline]
    func maxRuntimeU32(a: u32, b: u32)->u32 => @max(a, b)
    #[Swag.NoInline]
    func minRuntimeU64(a: u64, b: u64)->u64 => @min(a, b)
    #[Swag.NoInline]
    func maxRuntimeU64(a: u64, b: u64)->u64 => @max(a, b)

    #[Swag.NoInline]
    func minRuntimeF64(a: f64, b: f64)->f64 => @min(a, b)
    #[Swag.NoInline]
    func maxRuntimeF32(a: f32, b: f32)->f32 => @max(a, b)

    const S8Min = #run minRuntimeS8(-7's8, 3's8)
    const S8Max = #run maxRuntimeS8(-7's8, 3's8)
    const S16Min = #run minRuntimeS16(-300's16, 77's16)
    const S16Max = #run maxRuntimeS16(-300's16, 77's16)
    const S32Min = #run minRuntimeS32(-7, 3)
    const S32Max = #run maxRuntimeS32(-7, 3)
    const S64Min = #run minRuntimeS64(-5000000000's64, 3's64)
    const S64Max = #run maxRuntimeS64(-5000000000's64, 3's64)

    const U8Min = #run minRuntimeU8(4'u8, 9'u8)
    const U8Max = #run maxRuntimeU8(4'u8, 9'u8)
    const U16Min = #run minRuntimeU16(65000'u16, 12'u16)
    const U16Max = #run maxRuntimeU16(65000'u16, 12'u16)
    const U32Min = #run minRuntimeU32(4000000000'u32, 7'u32)
    const U32Max = #run maxRuntimeU32(4000000000'u32, 7'u32)
    const U64Min = #run minRuntimeU64(4'u64, 9'u64)
    const U64Max = #run maxRuntimeU64(4'u64, 9'u64)

    const F64Min = #run minRuntimeF64(6.5, 3.0)
    const F32Max = #run maxRuntimeF32(1.25'f32, 2.75'f32)

    #assert(S8Min == -7)
    #assert(S8Max == 3)
    #assert(S16Min == -300)
    #assert(S16Max == 77)
    #assert(S32Min == -7)
    #assert(S32Max == 3)
    #assert(S64Min == -5000000000)
    #assert(S64Max == 3)

    #assert(U8Min == 4)
    #assert(U8Max == 9)
    #assert(U16Min == 12)
    #assert(U16Max == 65000)
    #assert(U32Min == 7)
    #assert(U32Max == 4000000000)
    #assert(U64Min == 4)
    #assert(U64Max == 9)

    #assert(F64Min == 3.0)
    #assert(F32Max == 2.75)
}
