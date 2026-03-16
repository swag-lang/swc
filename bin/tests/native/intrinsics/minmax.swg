#global fileprivate // swc-option suite-test

#[Swag.NoInline]
func minS32(a: s32, b: s32)->s32 => @min(a, b)

#[Swag.NoInline]
func maxS32(a: s32, b: s32)->s32 => @max(a, b)

#[Swag.NoInline]
func minS64(a: s64, b: s64)->s64 => @min(a, b)

#[Swag.NoInline]
func maxS64(a: s64, b: s64)->s64 => @max(a, b)

#[Swag.NoInline]
func minU32(a: u32, b: u32)->u32 => @min(a, b)

#[Swag.NoInline]
func maxU32(a: u32, b: u32)->u32 => @max(a, b)

#[Swag.NoInline]
func minU64(a: u64, b: u64)->u64 => @min(a, b)

#[Swag.NoInline]
func maxU64(a: u64, b: u64)->u64 => @max(a, b)

#[Swag.NoInline]
func minF64(a: f64, b: f64)->f64 => @min(a, b)

#[Swag.NoInline]
func maxF32(a: f32, b: f32)->f32 => @max(a, b)

#test
{
    @assert(minS32(-7, 3) == -7)
    @assert(maxS32(-7, 3) == 3)
    @assert(minS64(-5000000000's64, 3's64) == -5000000000's64)
    @assert(maxS64(-5000000000's64, 3's64) == 3's64)
}

#test
{
    @assert(minU32(4000000000'u32, 7'u32) == 7'u32)
    @assert(maxU32(4000000000'u32, 7'u32) == 4000000000'u32)
    @assert(minU64(4'u64, 9'u64) == 4'u64)
    @assert(maxU64(4'u64, 9'u64) == 9'u64)
}

#test
{
    @assert(minF64(6.5'f64, 3.0'f64) == 3.0'f64)
    @assert(maxF32(1.25'f32, 2.75'f32) == 2.75'f32)
    @assert(minS32(9, 9) == 9)
    @assert(maxU64(11'u64, 11'u64) == 11'u64)
}
