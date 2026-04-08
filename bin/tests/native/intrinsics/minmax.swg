#global fileprivate //

// ============================================================
// Runtime wrappers — all types
// ============================================================

#[Swag.NoInline]
func minS8(a: s8, b: s8)->s8 => @min(a, b)

#[Swag.NoInline]
func maxS8(a: s8, b: s8)->s8 => @max(a, b)

#[Swag.NoInline]
func minS16(a: s16, b: s16)->s16 => @min(a, b)

#[Swag.NoInline]
func maxS16(a: s16, b: s16)->s16 => @max(a, b)

#[Swag.NoInline]
func minS32(a: s32, b: s32)->s32 => @min(a, b)

#[Swag.NoInline]
func maxS32(a: s32, b: s32)->s32 => @max(a, b)

#[Swag.NoInline]
func minS64(a: s64, b: s64)->s64 => @min(a, b)

#[Swag.NoInline]
func maxS64(a: s64, b: s64)->s64 => @max(a, b)

#[Swag.NoInline]
func minU8(a: u8, b: u8)->u8 => @min(a, b)

#[Swag.NoInline]
func maxU8(a: u8, b: u8)->u8 => @max(a, b)

#[Swag.NoInline]
func minU16(a: u16, b: u16)->u16 => @min(a, b)

#[Swag.NoInline]
func maxU16(a: u16, b: u16)->u16 => @max(a, b)

#[Swag.NoInline]
func minU32(a: u32, b: u32)->u32 => @min(a, b)

#[Swag.NoInline]
func maxU32(a: u32, b: u32)->u32 => @max(a, b)

#[Swag.NoInline]
func minU64(a: u64, b: u64)->u64 => @min(a, b)

#[Swag.NoInline]
func maxU64(a: u64, b: u64)->u64 => @max(a, b)

#[Swag.NoInline]
func minF32(a: f32, b: f32)->f32 => @min(a, b)

#[Swag.NoInline]
func maxF32(a: f32, b: f32)->f32 => @max(a, b)

#[Swag.NoInline]
func minF64(a: f64, b: f64)->f64 => @min(a, b)

#[Swag.NoInline]
func maxF64(a: f64, b: f64)->f64 => @max(a, b)

// ============================================================
// Compile-time — signed integers
// ============================================================

#test
{
    const a: s8 = @min(1's8, 2's8)
    const b: s8 = @max(1's8, 2's8)
    const c: s8 = @min(-128's8, 127's8)
    const d: s8 = @max(-128's8, 127's8)
    #assert(a == 1)
    #assert(b == 2)
    #assert(c == -128)
    #assert(d == 127)
}

#test
{
    const a: s16 = @min(-3's16, 7's16)
    const b: s16 = @max(-3's16, 7's16)
    #assert(a == -3)
    #assert(b == 7)
}

#test
{
    const a: s32 = @min(1's32, 2's32)
    const b: s32 = @max(1's32, 2's32)
    const c: s32 = @min(-1's32, 0's32)
    const d: s32 = @max(-1's32, 0's32)
    #assert(a == 1)
    #assert(b == 2)
    #assert(c == -1)
    #assert(d == 0)
}

#test
{
    const a: s64 = @min(-5's64, 3's64)
    const b: s64 = @max(-5's64, 3's64)
    #assert(a == -5)
    #assert(b == 3)
}

// ============================================================
// Compile-time — unsigned integers
// ============================================================

#test
{
    const a: u8 = @min(1'u8, 2'u8)
    const b: u8 = @max(1'u8, 2'u8)
    const c: u8 = @min(0'u8, 255'u8)
    const d: u8 = @max(0'u8, 255'u8)
    #assert(a == 1'u8)
    #assert(b == 2'u8)
    #assert(c == 0'u8)
    #assert(d == 255'u8)
}

#test
{
    const a: u16 = @min(3'u16, 1'u16)
    const b: u16 = @max(3'u16, 1'u16)
    #assert(a == 1'u16)
    #assert(b == 3'u16)
}

#test
{
    const a: u32 = @min(10'u32, 20'u32)
    const b: u32 = @max(10'u32, 20'u32)
    #assert(a == 10'u32)
    #assert(b == 20'u32)
}

#test
{
    const a: u64 = @min(1'u64, 0xFFFFFFFF_FFFFFFFF'u64)
    const b: u64 = @max(1'u64, 0xFFFFFFFF_FFFFFFFF'u64)
    #assert(a == 1'u64)
    #assert(b == 0xFFFFFFFF_FFFFFFFF'u64)
}

// ============================================================
// Compile-time — floats
// ============================================================

#test
{
    const a: f64 = @min(1.0'f64, 2.0'f64)
    const b: f64 = @max(1.0'f64, 2.0'f64)
    const c: f64 = @min(-100.0'f64, -50.0'f64)
    const d: f64 = @max(-100.0'f64, -50.0'f64)
    #assert(a == 1.0)
    #assert(b == 2.0)
    #assert(c == -100.0)
    #assert(d == -50.0)
}

// ============================================================
// Runtime — signed integers
// ============================================================

#test
{
    @assert(minS8(-7's8, 3's8) == -7's8)
    @assert(maxS8(-7's8, 3's8) == 3's8)
    @assert(minS8(-128's8, 127's8) == -128's8)
    @assert(maxS8(-128's8, 127's8) == 127's8)
    @assert(minS8(5's8, 5's8) == 5's8)
    @assert(maxS8(5's8, 5's8) == 5's8)
}

#test
{
    @assert(minS16(-321's16, 100's16) == -321's16)
    @assert(maxS16(-321's16, 100's16) == 100's16)
    @assert(minS16(0's16, 0's16) == 0's16)
}

#test
{
    @assert(minS32(-7, 3) == -7)
    @assert(maxS32(-7, 3) == 3)
    @assert(minS32(9, 9) == 9)
    @assert(maxS32(0, -1) == 0)
    @assert(minS32(0, -1) == -1)
}

#test
{
    @assert(minS64(-5000000000's64, 3's64) == -5000000000's64)
    @assert(maxS64(-5000000000's64, 3's64) == 3's64)
}

// ============================================================
// Runtime — unsigned integers
// ============================================================

#test
{
    @assert(minU8(1'u8, 200'u8) == 1'u8)
    @assert(maxU8(1'u8, 200'u8) == 200'u8)
    @assert(minU8(0'u8, 255'u8) == 0'u8)
    @assert(maxU8(0'u8, 255'u8) == 255'u8)
}

#test
{
    @assert(minU16(100'u16, 200'u16) == 100'u16)
    @assert(maxU16(100'u16, 200'u16) == 200'u16)
}

#test
{
    @assert(minU32(4000000000'u32, 7'u32) == 7'u32)
    @assert(maxU32(4000000000'u32, 7'u32) == 4000000000'u32)
}

#test
{
    @assert(minU64(4'u64, 9'u64) == 4'u64)
    @assert(maxU64(4'u64, 9'u64) == 9'u64)
    @assert(maxU64(11'u64, 11'u64) == 11'u64)
}

// ============================================================
// Runtime — floats
// ============================================================

#test
{
    @assert(minF32(1.25'f32, 2.75'f32) == 1.25'f32)
    @assert(maxF32(1.25'f32, 2.75'f32) == 2.75'f32)
    @assert(minF32(-1.0'f32, 1.0'f32) == -1.0'f32)
    @assert(maxF32(-1.0'f32, 1.0'f32) == 1.0'f32)
}

#test
{
    @assert(minF64(6.5'f64, 3.0'f64) == 3.0'f64)
    @assert(maxF64(6.5'f64, 3.0'f64) == 6.5'f64)
    @assert(minF64(-100.0'f64, -50.0'f64) == -100.0'f64)
    @assert(maxF64(-100.0'f64, -50.0'f64) == -50.0'f64)
}

// Commutativity
#test
{
    @assert(minS32(3, -7) == minS32(-7, 3))
    @assert(maxS32(3, -7) == maxS32(-7, 3))
    @assert(minU64(100'u64, 200'u64) == minU64(200'u64, 100'u64))
    @assert(maxU64(100'u64, 200'u64) == maxU64(200'u64, 100'u64))
    @assert(minF64(1.5'f64, 2.5'f64) == minF64(2.5'f64, 1.5'f64))
    @assert(maxF32(1.0'f32, 9.0'f32) == maxF32(9.0'f32, 1.0'f32))
}
