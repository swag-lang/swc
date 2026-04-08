#global fileprivate //

#[Swag.NoInline]
func absS8(value: s8)->s8 => @abs(value)

#[Swag.NoInline]
func absS16(value: s16)->s16 => @abs(value)

#[Swag.NoInline]
func absS32(value: s32)->s32 => @abs(value)

#[Swag.NoInline]
func absS64(value: s64)->s64 => @abs(value)

#[Swag.NoInline]
func absF32(value: f32)->f32 => @abs(value)

#[Swag.NoInline]
func absF64(value: f64)->f64 => @abs(value)

// Compile-time — integers
#test
{
    const a: s8 = @abs(-7's8)
    const b: s8 = @abs(0's8)
    const c: s8 = @abs(7's8)
    #assert(a == 7's8)
    #assert(b == 0's8)
    #assert(c == 7's8)

    const d: s16 = @abs(-321's16)
    const e: s16 = @abs(0's16)
    #assert(d == 321's16)
    #assert(e == 0's16)

    const f: s32 = @abs(-123456's32)
    const g: s32 = @abs(0's32)
    #assert(f == 123456)
    #assert(g == 0)

    const h: s64 = @abs(-5000000000's64)
    const i: s64 = @abs(0's64)
    #assert(h == 5000000000's64)
    #assert(i == 0's64)
}

// Compile-time — floats
#test
{
    const a: f64 = @abs(-3.5'f32)
    const b: f64 = @abs(0.0'f32)
    const c: f64 = @abs(3.5'f32)
    #assert(a == 3.5)
    #assert(b == 0.0)
    #assert(c == 3.5)
}

#test
{
    const a: f64 = @abs(-9.25'f64)
    const b: f64 = @abs(0.0'f64)
    const c: f64 = @abs(9.25'f64)
    #assert(a == 9.25)
    #assert(b == 0.0)
    #assert(c == 9.25)
}

// Runtime — s8
#test
{
    @assert(absS8(-7's8) == 7's8)
    @assert(absS8(0's8) == 0's8)
    @assert(absS8(7's8) == 7's8)
    @assert(absS8(-1's8) == 1's8)
    @assert(absS8(127's8) == 127's8)
}

// Runtime — s16
#test
{
    @assert(absS16(-321's16) == 321's16)
    @assert(absS16(0's16) == 0's16)
    @assert(absS16(321's16) == 321's16)
    @assert(absS16(-1's16) == 1's16)
    @assert(absS16(32767's16) == 32767's16)
}

// Runtime — s32
#test
{
    @assert(absS32(-123456) == 123456)
    @assert(absS32(0) == 0)
    @assert(absS32(123456) == 123456)
    @assert(absS32(-1) == 1)
    @assert(absS32(4) == 4)
}

// Runtime — s64
#test
{
    @assert(absS64(-5000000000's64) == 5000000000's64)
    @assert(absS64(0's64) == 0's64)
    @assert(absS64(5000000000's64) == 5000000000's64)
    @assert(absS64(-1's64) == 1's64)
}

// Runtime — f32
#test
{
    @assert(absF32(-3.5'f32) == 3.5'f32)
    @assert(absF32(0.0'f32) == 0.0'f32)
    @assert(absF32(3.5'f32) == 3.5'f32)
    @assert(absF32(-0.001'f32) == 0.001'f32)
    @assert(absF32(100.0'f32) == 100.0'f32)
}

// Runtime — f64
#test
{
    @assert(absF64(-9.25'f64) == 9.25'f64)
    @assert(absF64(0.0'f64) == 0.0'f64)
    @assert(absF64(9.25'f64) == 9.25'f64)
    @assert(absF64(-0.0001'f64) == 0.0001'f64)
    @assert(absF64(4.25'f64) == 4.25'f64)
}
