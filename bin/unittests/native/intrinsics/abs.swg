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
    const a: s8 = Swag.abs(-7's8)
    const b: s8 = Swag.abs(0's8)
    const c: s8 = Swag.abs(7's8)
    #assert(a == 7's8)
    #assert(b == 0's8)
    #assert(c == 7's8)

    const d: s16 = Swag.abs(-321's16)
    const e: s16 = Swag.abs(0's16)
    #assert(d == 321's16)
    #assert(e == 0's16)

    const f: s32 = Swag.abs(-123456's32)
    const g: s32 = Swag.abs(0's32)
    #assert(f == 123456)
    #assert(g == 0)

    const h: s64 = Swag.abs(-5000000000's64)
    const i: s64 = Swag.abs(0's64)
    #assert(h == 5000000000's64)
    #assert(i == 0's64)
}

// Compile-time — floats
#test
{
    const a: f64 = Swag.abs(-3.5'f32)
    const b: f64 = Swag.abs(0.0'f32)
    const c: f64 = Swag.abs(3.5'f32)
    #assert(a == 3.5)
    #assert(b == 0.0)
    #assert(c == 3.5)
}

#test
{
    const a: f64 = Swag.abs(-9.25'f64)
    const b: f64 = Swag.abs(0.0'f64)
    const c: f64 = Swag.abs(9.25'f64)
    #assert(a == 9.25)
    #assert(b == 0.0)
    #assert(c == 9.25)
}

// Runtime — s8
#test
{
    Swag.assert(absS8(-7's8) == 7's8)
    Swag.assert(absS8(0's8) == 0's8)
    Swag.assert(absS8(7's8) == 7's8)
    Swag.assert(absS8(-1's8) == 1's8)
    Swag.assert(absS8(127's8) == 127's8)
}

// Runtime — s16
#test
{
    Swag.assert(absS16(-321's16) == 321's16)
    Swag.assert(absS16(0's16) == 0's16)
    Swag.assert(absS16(321's16) == 321's16)
    Swag.assert(absS16(-1's16) == 1's16)
    Swag.assert(absS16(32767's16) == 32767's16)
}

// Runtime — s32
#test
{
    Swag.assert(absS32(-123456) == 123456)
    Swag.assert(absS32(0) == 0)
    Swag.assert(absS32(123456) == 123456)
    Swag.assert(absS32(-1) == 1)
    Swag.assert(absS32(4) == 4)
}

// Runtime — s64
#test
{
    Swag.assert(absS64(-5000000000's64) == 5000000000's64)
    Swag.assert(absS64(0's64) == 0's64)
    Swag.assert(absS64(5000000000's64) == 5000000000's64)
    Swag.assert(absS64(-1's64) == 1's64)
}

// Runtime — f32
#test
{
    Swag.assert(absF32(-3.5'f32) == 3.5'f32)
    Swag.assert(absF32(0.0'f32) == 0.0'f32)
    Swag.assert(absF32(3.5'f32) == 3.5'f32)
    Swag.assert(absF32(-0.001'f32) == 0.001'f32)
    Swag.assert(absF32(100.0'f32) == 100.0'f32)
}

// Runtime — f64
#test
{
    Swag.assert(absF64(-9.25'f64) == 9.25'f64)
    Swag.assert(absF64(0.0'f64) == 0.0'f64)
    Swag.assert(absF64(9.25'f64) == 9.25'f64)
    Swag.assert(absF64(-0.0001'f64) == 0.0001'f64)
    Swag.assert(absF64(4.25'f64) == 4.25'f64)
}

// Strict aliases
#test
{
    const a = Swag.abs(cast(AbsStrictS32) -42)
    const b = Swag.abs(cast(AbsStrictF32) -1.5'f32)

    #assert(#typeof(a) == AbsStrictS32)
    #assert(#typeof(b) == AbsStrictF32)

    Swag.assert(a == cast(AbsStrictS32) 42)
    Swag.assert(b == cast(AbsStrictF32) 1.5'f32)
}

#test
{
    let a = absStrictS32(cast(AbsStrictS32) -123)
    let b = absStrictF32(cast(AbsStrictF32) -2.25'f32)

    #assert(#typeof(a) == AbsStrictS32)
    #assert(#typeof(b) == AbsStrictF32)

    Swag.assert(a == cast(AbsStrictS32) 123)
    Swag.assert(b == cast(AbsStrictF32) 2.25'f32)
}
