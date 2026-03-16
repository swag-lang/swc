#global fileprivate // swc-option suite-test

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

#test
{
    var s8Value: s8 = -7
    var s16Value: s16 = -321
    var s32Value: s32 = -123456
    var s64Value: s64 = -5000000000's64
    var f32Value: f32 = -3.5'f32
    var f64Value: f64 = -9.25'f64

    @assert(absS8(s8Value) == 7's8)
    @assert(absS16(s16Value) == 321's16)
    @assert(absS32(s32Value) == 123456)
    @assert(absS64(s64Value) == 5000000000's64)
    @assert(absF32(f32Value) == 3.5'f32)
    @assert(absF64(f64Value) == 9.25'f64)
}

#test
{
    @assert(absS32(0) == 0)
    @assert(absF64(4.25'f64) == 4.25'f64)
}
