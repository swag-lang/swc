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
    const a: s8 = Swag.min(1_s8, 2_s8)
    const b: s8 = Swag.max(1_s8, 2_s8)
    const c: s8 = Swag.min(-128_s8, 127_s8)
    const d: s8 = Swag.max(-128_s8, 127_s8)
    #assert(a == 1)
    #assert(b == 2)
    #assert(c == -128)
    #assert(d == 127)
}

#test
{
    const a: s16 = Swag.min(-3_s16, 7_s16)
    const b: s16 = Swag.max(-3_s16, 7_s16)
    #assert(a == -3)
    #assert(b == 7)
}

#test
{
    const a: s32 = Swag.min(1_s32, 2_s32)
    const b: s32 = Swag.max(1_s32, 2_s32)
    const c: s32 = Swag.min(-1_s32, 0_s32)
    const d: s32 = Swag.max(-1_s32, 0_s32)
    #assert(a == 1)
    #assert(b == 2)
    #assert(c == -1)
    #assert(d == 0)
}

#test
{
    const a: s64 = Swag.min(-5_s64, 3_s64)
    const b: s64 = Swag.max(-5_s64, 3_s64)
    #assert(a == -5)
    #assert(b == 3)
}

// ============================================================
// Compile-time — unsigned integers
// ============================================================

#test
{
    const a: u8 = Swag.min(1_u8, 2_u8)
    const b: u8 = Swag.max(1_u8, 2_u8)
    const c: u8 = Swag.min(0_u8, 255_u8)
    const d: u8 = Swag.max(0_u8, 255_u8)
    #assert(a == 1_u8)
    #assert(b == 2_u8)
    #assert(c == 0_u8)
    #assert(d == 255_u8)
}

#test
{
    const a: u16 = Swag.min(3_u16, 1_u16)
    const b: u16 = Swag.max(3_u16, 1_u16)
    #assert(a == 1_u16)
    #assert(b == 3_u16)
}

#test
{
    const a: u32 = Swag.min(10_u32, 20_u32)
    const b: u32 = Swag.max(10_u32, 20_u32)
    #assert(a == 10_u32)
    #assert(b == 20_u32)
}

#test
{
    const a: u64 = Swag.min(1_u64, 0xFFFFFFFF_FFFFFFFF_u64)
    const b: u64 = Swag.max(1_u64, 0xFFFFFFFF_FFFFFFFF_u64)
    #assert(a == 1_u64)
    #assert(b == 0xFFFFFFFF_FFFFFFFF_u64)
}

// ============================================================
// Compile-time — floats
// ============================================================

#test
{
    const a: f64 = Swag.min(1.0_f64, 2.0_f64)
    const b: f64 = Swag.max(1.0_f64, 2.0_f64)
    const c: f64 = Swag.min(-100.0_f64, -50.0_f64)
    const d: f64 = Swag.max(-100.0_f64, -50.0_f64)
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
    Swag.require(minS8(-7_s8, 3_s8) == -7_s8)
    Swag.require(maxS8(-7_s8, 3_s8) == 3_s8)
    Swag.require(minS8(-128_s8, 127_s8) == -128_s8)
    Swag.require(maxS8(-128_s8, 127_s8) == 127_s8)
    Swag.require(minS8(5_s8, 5_s8) == 5_s8)
    Swag.require(maxS8(5_s8, 5_s8) == 5_s8)
}

#test
{
    Swag.require(minS16(-321_s16, 100_s16) == -321_s16)
    Swag.require(maxS16(-321_s16, 100_s16) == 100_s16)
    Swag.require(minS16(0_s16, 0_s16) == 0_s16)
}

#test
{
    Swag.require(minS32(-7, 3) == -7)
    Swag.require(maxS32(-7, 3) == 3)
    Swag.require(minS32(9, 9) == 9)
    Swag.require(maxS32(0, -1) == 0)
    Swag.require(minS32(0, -1) == -1)
}

#test
{
    Swag.require(minS64(-5000000000_s64, 3_s64) == -5000000000_s64)
    Swag.require(maxS64(-5000000000_s64, 3_s64) == 3_s64)
}

// ============================================================
// Runtime — unsigned integers
// ============================================================

#test
{
    Swag.require(minU8(1_u8, 200_u8) == 1_u8)
    Swag.require(maxU8(1_u8, 200_u8) == 200_u8)
    Swag.require(minU8(0_u8, 255_u8) == 0_u8)
    Swag.require(maxU8(0_u8, 255_u8) == 255_u8)
}

#test
{
    Swag.require(minU16(100_u16, 200_u16) == 100_u16)
    Swag.require(maxU16(100_u16, 200_u16) == 200_u16)
}

#test
{
    Swag.require(minU32(4000000000_u32, 7_u32) == 7_u32)
    Swag.require(maxU32(4000000000_u32, 7_u32) == 4000000000_u32)
}

#test
{
    Swag.require(minU64(4_u64, 9_u64) == 4_u64)
    Swag.require(maxU64(4_u64, 9_u64) == 9_u64)
    Swag.require(maxU64(11_u64, 11_u64) == 11_u64)
}

// ============================================================
// Runtime — floats
// ============================================================

#test
{
    Swag.require(minF32(1.25_f32, 2.75_f32) == 1.25_f32)
    Swag.require(maxF32(1.25_f32, 2.75_f32) == 2.75_f32)
    Swag.require(minF32(-1.0_f32, 1.0_f32) == -1.0_f32)
    Swag.require(maxF32(-1.0_f32, 1.0_f32) == 1.0_f32)
}

#test
{
    Swag.require(minF64(6.5_f64, 3.0_f64) == 3.0_f64)
    Swag.require(maxF64(6.5_f64, 3.0_f64) == 6.5_f64)
    Swag.require(minF64(-100.0_f64, -50.0_f64) == -100.0_f64)
    Swag.require(maxF64(-100.0_f64, -50.0_f64) == -50.0_f64)
}

// Commutativity
#test
{
    Swag.require(minS32(3, -7) == minS32(-7, 3))
    Swag.require(maxS32(3, -7) == maxS32(-7, 3))
    Swag.require(minU64(100_u64, 200_u64) == minU64(200_u64, 100_u64))
    Swag.require(maxU64(100_u64, 200_u64) == maxU64(200_u64, 100_u64))
    Swag.require(minF64(1.5_f64, 2.5_f64) == minF64(2.5_f64, 1.5_f64))
    Swag.require(maxF32(1.0_f32, 9.0_f32) == maxF32(9.0_f32, 1.0_f32))
}

// Strict aliases
#test
{
    const a = Swag.min(cast(MinMaxStrictS32, -5), cast(MinMaxStrictS32, 3))
    const b = Swag.max(cast(MinMaxStrictS32, -5), cast(MinMaxStrictS32, 3))
    const c = Swag.min(cast(MinMaxStrictU32, 10), cast(MinMaxStrictU32, 4))
    const d = Swag.max(cast(MinMaxStrictF32, 1.5_f32), cast(MinMaxStrictF32, 2.5_f32))

    #assert(#typeof(a) == MinMaxStrictS32)
    #assert(#typeof(b) == MinMaxStrictS32)
    #assert(#typeof(c) == MinMaxStrictU32)
    #assert(#typeof(d) == MinMaxStrictF32)

    Swag.require(a == cast(MinMaxStrictS32, -5))
    Swag.require(b == cast(MinMaxStrictS32, 3))
    Swag.require(c == cast(MinMaxStrictU32, 4))
    Swag.require(d == cast(MinMaxStrictF32, 2.5_f32))
}

#test
{
    let si = minStrictS32(cast(MinMaxStrictS32, 7), cast(MinMaxStrictS32, -2))
    let sx = maxStrictS32(cast(MinMaxStrictS32, 7), cast(MinMaxStrictS32, -2))
    let ui = minStrictU32(cast(MinMaxStrictU32, 9), cast(MinMaxStrictU32, 11))
    let ux = maxStrictU32(cast(MinMaxStrictU32, 9), cast(MinMaxStrictU32, 11))
    let fi = minStrictF32(cast(MinMaxStrictF32, 4.5_f32), cast(MinMaxStrictF32, 2.25_f32))
    let fx = maxStrictF32(cast(MinMaxStrictF32, 4.5_f32), cast(MinMaxStrictF32, 2.25_f32))

    #assert(#typeof(si) == MinMaxStrictS32)
    #assert(#typeof(sx) == MinMaxStrictS32)
    #assert(#typeof(ui) == MinMaxStrictU32)
    #assert(#typeof(ux) == MinMaxStrictU32)
    #assert(#typeof(fi) == MinMaxStrictF32)
    #assert(#typeof(fx) == MinMaxStrictF32)

    Swag.require(si == cast(MinMaxStrictS32, -2))
    Swag.require(sx == cast(MinMaxStrictS32, 7))
    Swag.require(ui == cast(MinMaxStrictU32, 9))
    Swag.require(ux == cast(MinMaxStrictU32, 11))
    Swag.require(fi == cast(MinMaxStrictF32, 2.25_f32))
    Swag.require(fx == cast(MinMaxStrictF32, 4.5_f32))
}
