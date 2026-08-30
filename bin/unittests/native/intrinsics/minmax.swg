#global private     //

// ============================================================
// Runtime wrappers — all types
// ============================================================

#[Swag.NoInline]
func minS8(a: s8, b: s8)->s8 => Swag.min(a, b)

#[Swag.NoInline]
func maxS8(a: s8, b: s8)->s8 => Swag.max(a, b)

#[Swag.NoInline]
func minS16(a: s16, b: s16)->s16 => Swag.min(a, b)

#[Swag.NoInline]
func maxS16(a: s16, b: s16)->s16 => Swag.max(a, b)

#[Swag.NoInline]
func minS32(a: s32, b: s32)->s32 => Swag.min(a, b)

#[Swag.NoInline]
func maxS32(a: s32, b: s32)->s32 => Swag.max(a, b)

#[Swag.NoInline]
func minS64(a: s64, b: s64)->s64 => Swag.min(a, b)

#[Swag.NoInline]
func maxS64(a: s64, b: s64)->s64 => Swag.max(a, b)

#[Swag.NoInline]
func minU8(a: u8, b: u8)->u8 => Swag.min(a, b)

#[Swag.NoInline]
func maxU8(a: u8, b: u8)->u8 => Swag.max(a, b)

#[Swag.NoInline]
func minU16(a: u16, b: u16)->u16 => Swag.min(a, b)

#[Swag.NoInline]
func maxU16(a: u16, b: u16)->u16 => Swag.max(a, b)

#[Swag.NoInline]
func minU32(a: u32, b: u32)->u32 => Swag.min(a, b)

#[Swag.NoInline]
func maxU32(a: u32, b: u32)->u32 => Swag.max(a, b)

#[Swag.NoInline]
func minU64(a: u64, b: u64)->u64 => Swag.min(a, b)

#[Swag.NoInline]
func maxU64(a: u64, b: u64)->u64 => Swag.max(a, b)

#[Swag.NoInline]
func minF32(a: f32, b: f32)->f32 => Swag.min(a, b)

#[Swag.NoInline]
func maxF32(a: f32, b: f32)->f32 => Swag.max(a, b)

#[Swag.NoInline]
func minF64(a: f64, b: f64)->f64 => Swag.min(a, b)

#[Swag.NoInline]
func maxF64(a: f64, b: f64)->f64 => Swag.max(a, b)

#[Swag.Strict]
alias MinMaxStrictS32 = s32

#[Swag.Strict]
alias MinMaxStrictU32 = u32

#[Swag.Strict]
alias MinMaxStrictF32 = f32

#[Swag.NoInline]
func minStrictS32(a: MinMaxStrictS32, b: MinMaxStrictS32)->MinMaxStrictS32 => Swag.min(a, b)

#[Swag.NoInline]
func maxStrictS32(a: MinMaxStrictS32, b: MinMaxStrictS32)->MinMaxStrictS32 => Swag.max(a, b)

#[Swag.NoInline]
func minStrictU32(a: MinMaxStrictU32, b: MinMaxStrictU32)->MinMaxStrictU32 => Swag.min(a, b)

#[Swag.NoInline]
func maxStrictU32(a: MinMaxStrictU32, b: MinMaxStrictU32)->MinMaxStrictU32 => Swag.max(a, b)

#[Swag.NoInline]
func minStrictF32(a: MinMaxStrictF32, b: MinMaxStrictF32)->MinMaxStrictF32 => Swag.min(a, b)

#[Swag.NoInline]
func maxStrictF32(a: MinMaxStrictF32, b: MinMaxStrictF32)->MinMaxStrictF32 => Swag.max(a, b)

// ============================================================
// Compile-time — signed integers
// ============================================================

#test
{
    const a: s8 = Swag.min(1's8, 2's8)
    const b: s8 = Swag.max(1's8, 2's8)
    const c: s8 = Swag.min(-128's8, 127's8)
    const d: s8 = Swag.max(-128's8, 127's8)
    #assert(a == 1)
    #assert(b == 2)
    #assert(c == -128)
    #assert(d == 127)
}

#test
{
    const a: s16 = Swag.min(-3's16, 7's16)
    const b: s16 = Swag.max(-3's16, 7's16)
    #assert(a == -3)
    #assert(b == 7)
}

#test
{
    const a: s32 = Swag.min(1's32, 2's32)
    const b: s32 = Swag.max(1's32, 2's32)
    const c: s32 = Swag.min(-1's32, 0's32)
    const d: s32 = Swag.max(-1's32, 0's32)
    #assert(a == 1)
    #assert(b == 2)
    #assert(c == -1)
    #assert(d == 0)
}

#test
{
    const a: s64 = Swag.min(-5's64, 3's64)
    const b: s64 = Swag.max(-5's64, 3's64)
    #assert(a == -5)
    #assert(b == 3)
}

// ============================================================
// Compile-time — unsigned integers
// ============================================================

#test
{
    const a: u8 = Swag.min(1'u8, 2'u8)
    const b: u8 = Swag.max(1'u8, 2'u8)
    const c: u8 = Swag.min(0'u8, 255'u8)
    const d: u8 = Swag.max(0'u8, 255'u8)
    #assert(a == 1'u8)
    #assert(b == 2'u8)
    #assert(c == 0'u8)
    #assert(d == 255'u8)
}

#test
{
    const a: u16 = Swag.min(3'u16, 1'u16)
    const b: u16 = Swag.max(3'u16, 1'u16)
    #assert(a == 1'u16)
    #assert(b == 3'u16)
}

#test
{
    const a: u32 = Swag.min(10'u32, 20'u32)
    const b: u32 = Swag.max(10'u32, 20'u32)
    #assert(a == 10'u32)
    #assert(b == 20'u32)
}

#test
{
    const a: u64 = Swag.min(1'u64, 0xFFFFFFFF_FFFFFFFF'u64)
    const b: u64 = Swag.max(1'u64, 0xFFFFFFFF_FFFFFFFF'u64)
    #assert(a == 1'u64)
    #assert(b == 0xFFFFFFFF_FFFFFFFF'u64)
}

// ============================================================
// Compile-time — floats
// ============================================================

#test
{
    const a: f64 = Swag.min(1.0'f64, 2.0'f64)
    const b: f64 = Swag.max(1.0'f64, 2.0'f64)
    const c: f64 = Swag.min(-100.0'f64, -50.0'f64)
    const d: f64 = Swag.max(-100.0'f64, -50.0'f64)
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
    Swag.assert(minS8(-7's8, 3's8) == -7's8)
    Swag.assert(maxS8(-7's8, 3's8) == 3's8)
    Swag.assert(minS8(-128's8, 127's8) == -128's8)
    Swag.assert(maxS8(-128's8, 127's8) == 127's8)
    Swag.assert(minS8(5's8, 5's8) == 5's8)
    Swag.assert(maxS8(5's8, 5's8) == 5's8)
}

#test
{
    Swag.assert(minS16(-321's16, 100's16) == -321's16)
    Swag.assert(maxS16(-321's16, 100's16) == 100's16)
    Swag.assert(minS16(0's16, 0's16) == 0's16)
}

#test
{
    Swag.assert(minS32(-7, 3) == -7)
    Swag.assert(maxS32(-7, 3) == 3)
    Swag.assert(minS32(9, 9) == 9)
    Swag.assert(maxS32(0, -1) == 0)
    Swag.assert(minS32(0, -1) == -1)
}

#test
{
    Swag.assert(minS64(-5000000000's64, 3's64) == -5000000000's64)
    Swag.assert(maxS64(-5000000000's64, 3's64) == 3's64)
}

// ============================================================
// Runtime — unsigned integers
// ============================================================

#test
{
    Swag.assert(minU8(1'u8, 200'u8) == 1'u8)
    Swag.assert(maxU8(1'u8, 200'u8) == 200'u8)
    Swag.assert(minU8(0'u8, 255'u8) == 0'u8)
    Swag.assert(maxU8(0'u8, 255'u8) == 255'u8)
}

#test
{
    Swag.assert(minU16(100'u16, 200'u16) == 100'u16)
    Swag.assert(maxU16(100'u16, 200'u16) == 200'u16)
}

#test
{
    Swag.assert(minU32(4000000000'u32, 7'u32) == 7'u32)
    Swag.assert(maxU32(4000000000'u32, 7'u32) == 4000000000'u32)
}

#test
{
    Swag.assert(minU64(4'u64, 9'u64) == 4'u64)
    Swag.assert(maxU64(4'u64, 9'u64) == 9'u64)
    Swag.assert(maxU64(11'u64, 11'u64) == 11'u64)
}

// ============================================================
// Runtime — floats
// ============================================================

#test
{
    Swag.assert(minF32(1.25'f32, 2.75'f32) == 1.25'f32)
    Swag.assert(maxF32(1.25'f32, 2.75'f32) == 2.75'f32)
    Swag.assert(minF32(-1.0'f32, 1.0'f32) == -1.0'f32)
    Swag.assert(maxF32(-1.0'f32, 1.0'f32) == 1.0'f32)
}

#test
{
    Swag.assert(minF64(6.5'f64, 3.0'f64) == 3.0'f64)
    Swag.assert(maxF64(6.5'f64, 3.0'f64) == 6.5'f64)
    Swag.assert(minF64(-100.0'f64, -50.0'f64) == -100.0'f64)
    Swag.assert(maxF64(-100.0'f64, -50.0'f64) == -50.0'f64)
}

// Commutativity
#test
{
    Swag.assert(minS32(3, -7) == minS32(-7, 3))
    Swag.assert(maxS32(3, -7) == maxS32(-7, 3))
    Swag.assert(minU64(100'u64, 200'u64) == minU64(200'u64, 100'u64))
    Swag.assert(maxU64(100'u64, 200'u64) == maxU64(200'u64, 100'u64))
    Swag.assert(minF64(1.5'f64, 2.5'f64) == minF64(2.5'f64, 1.5'f64))
    Swag.assert(maxF32(1.0'f32, 9.0'f32) == maxF32(9.0'f32, 1.0'f32))
}

// Strict aliases
#test
{
    const a = Swag.min(cast(MinMaxStrictS32) -5, cast(MinMaxStrictS32) 3)
    const b = Swag.max(cast(MinMaxStrictS32) -5, cast(MinMaxStrictS32) 3)
    const c = Swag.min(cast(MinMaxStrictU32) 10, cast(MinMaxStrictU32) 4)
    const d = Swag.max(cast(MinMaxStrictF32) 1.5'f32, cast(MinMaxStrictF32) 2.5'f32)

    #assert(#typeof(a) == MinMaxStrictS32)
    #assert(#typeof(b) == MinMaxStrictS32)
    #assert(#typeof(c) == MinMaxStrictU32)
    #assert(#typeof(d) == MinMaxStrictF32)

    Swag.assert(a == cast(MinMaxStrictS32) -5)
    Swag.assert(b == cast(MinMaxStrictS32) 3)
    Swag.assert(c == cast(MinMaxStrictU32) 4)
    Swag.assert(d == cast(MinMaxStrictF32) 2.5'f32)
}

#test
{
    let si = minStrictS32(cast(MinMaxStrictS32) 7, cast(MinMaxStrictS32) -2)
    let sx = maxStrictS32(cast(MinMaxStrictS32) 7, cast(MinMaxStrictS32) -2)
    let ui = minStrictU32(cast(MinMaxStrictU32) 9, cast(MinMaxStrictU32) 11)
    let ux = maxStrictU32(cast(MinMaxStrictU32) 9, cast(MinMaxStrictU32) 11)
    let fi = minStrictF32(cast(MinMaxStrictF32) 4.5'f32, cast(MinMaxStrictF32) 2.25'f32)
    let fx = maxStrictF32(cast(MinMaxStrictF32) 4.5'f32, cast(MinMaxStrictF32) 2.25'f32)

    #assert(#typeof(si) == MinMaxStrictS32)
    #assert(#typeof(sx) == MinMaxStrictS32)
    #assert(#typeof(ui) == MinMaxStrictU32)
    #assert(#typeof(ux) == MinMaxStrictU32)
    #assert(#typeof(fi) == MinMaxStrictF32)
    #assert(#typeof(fx) == MinMaxStrictF32)

    Swag.assert(si == cast(MinMaxStrictS32) -2)
    Swag.assert(sx == cast(MinMaxStrictS32) 7)
    Swag.assert(ui == cast(MinMaxStrictU32) 9)
    Swag.assert(ux == cast(MinMaxStrictU32) 11)
    Swag.assert(fi == cast(MinMaxStrictF32) 2.25'f32)
    Swag.assert(fx == cast(MinMaxStrictF32) 4.5'f32)
}
