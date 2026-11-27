#global private     //

#[Swag.NoInline]
func absS8(value: s8)->s8 => Swag.abs(value)

#[Swag.NoInline]
func absS16(value: s16)->s16 => Swag.abs(value)

#[Swag.NoInline]
func absS32(value: s32)->s32 => Swag.abs(value)

#[Swag.NoInline]
func absS64(value: s64)->s64 => Swag.abs(value)

#[Swag.NoInline]
func absF32(value: f32)->f32 => Swag.abs(value)

#[Swag.NoInline]
func absF64(value: f64)->f64 => Swag.abs(value)

#[Swag.Strict]
alias AbsStrictS32 = s32

#[Swag.Strict]
alias AbsStrictF32 = f32

#[Swag.NoInline]
func absStrictS32(value: AbsStrictS32)->AbsStrictS32 => Swag.abs(value)

#[Swag.NoInline]
func absStrictF32(value: AbsStrictF32)->AbsStrictF32 => Swag.abs(value)

// Compile-time — integers
#test
{
    const a: s8 = Swag.abs(-7_s8)
    const b: s8 = Swag.abs(0_s8)
    const c: s8 = Swag.abs(7_s8)
    #assert(a == 7_s8)
    #assert(b == 0_s8)
    #assert(c == 7_s8)

    const d: s16 = Swag.abs(-321_s16)
    const e: s16 = Swag.abs(0_s16)
    #assert(d == 321_s16)
    #assert(e == 0_s16)

    const f: s32 = Swag.abs(-123456_s32)
    const g: s32 = Swag.abs(0_s32)
    #assert(f == 123456)
    #assert(g == 0)

    const h: s64 = Swag.abs(-5000000000_s64)
    const i: s64 = Swag.abs(0_s64)
    #assert(h == 5000000000_s64)
    #assert(i == 0_s64)
}

// Compile-time — floats
#test
{
    const a: f64 = Swag.abs(-3.5_f32)
    const b: f64 = Swag.abs(0.0_f32)
    const c: f64 = Swag.abs(3.5_f32)
    #assert(a == 3.5)
    #assert(b == 0.0)
    #assert(c == 3.5)
}

#test
{
    const a: f64 = Swag.abs(-9.25_f64)
    const b: f64 = Swag.abs(0.0_f64)
    const c: f64 = Swag.abs(9.25_f64)
    #assert(a == 9.25)
    #assert(b == 0.0)
    #assert(c == 9.25)
}

// Runtime — s8
#test
{
    Swag.require(absS8(-7_s8) == 7_s8)
    Swag.require(absS8(0_s8) == 0_s8)
    Swag.require(absS8(7_s8) == 7_s8)
    Swag.require(absS8(-1_s8) == 1_s8)
    Swag.require(absS8(127_s8) == 127_s8)
}

// Runtime — s16
#test
{
    Swag.require(absS16(-321_s16) == 321_s16)
    Swag.require(absS16(0_s16) == 0_s16)
    Swag.require(absS16(321_s16) == 321_s16)
    Swag.require(absS16(-1_s16) == 1_s16)
    Swag.require(absS16(32767_s16) == 32767_s16)
}

// Runtime — s32
#test
{
    Swag.require(absS32(-123456) == 123456)
    Swag.require(absS32(0) == 0)
    Swag.require(absS32(123456) == 123456)
    Swag.require(absS32(-1) == 1)
    Swag.require(absS32(4) == 4)
}

// Runtime — s64
#test
{
    Swag.require(absS64(-5000000000_s64) == 5000000000_s64)
    Swag.require(absS64(0_s64) == 0_s64)
    Swag.require(absS64(5000000000_s64) == 5000000000_s64)
    Swag.require(absS64(-1_s64) == 1_s64)
}

// Runtime — f32
#test
{
    Swag.require(absF32(-3.5_f32) == 3.5_f32)
    Swag.require(absF32(0.0_f32) == 0.0_f32)
    Swag.require(absF32(3.5_f32) == 3.5_f32)
    Swag.require(absF32(-0.001_f32) == 0.001_f32)
    Swag.require(absF32(100.0_f32) == 100.0_f32)
}

// Runtime — f64
#test
{
    Swag.require(absF64(-9.25_f64) == 9.25_f64)
    Swag.require(absF64(0.0_f64) == 0.0_f64)
    Swag.require(absF64(9.25_f64) == 9.25_f64)
    Swag.require(absF64(-0.0001_f64) == 0.0001_f64)
    Swag.require(absF64(4.25_f64) == 4.25_f64)
}

// Strict aliases
#test
{
    const a = Swag.abs(cast(AbsStrictS32, -42))
    const b = Swag.abs(cast(AbsStrictF32, -1.5_f32))

    #assert(#typeof(a) == AbsStrictS32)
    #assert(#typeof(b) == AbsStrictF32)

    Swag.require(a == cast(AbsStrictS32, 42))
    Swag.require(b == cast(AbsStrictF32, 1.5_f32))
}

#test
{
    let a = absStrictS32(cast(AbsStrictS32, -123))
    let b = absStrictF32(cast(AbsStrictF32, -2.25_f32))

    #assert(#typeof(a) == AbsStrictS32)
    #assert(#typeof(b) == AbsStrictF32)

    Swag.require(a == cast(AbsStrictS32, 123))
    Swag.require(b == cast(AbsStrictF32, 2.25_f32))
}
