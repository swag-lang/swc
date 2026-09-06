#global private

var gFloatF32: f32
var gFloatF64: f64
func takes_f32(v: f32) { gFloatF32 = v }
func takes_f64(v: f64) { gFloatF64 = v }

#[Swag.NoInline]
func float32ToU64(value: f32)->u64 { return cast(u64) value }

#[Swag.NoInline]
func float64ToU64(value: f64)->u64 { return cast(u64) value }

// Exercise both sides of the signed conversion boundary and the largest source
// value below 2^64. The inputs are exact in their respective floating-point types.
#test
{
    Swag.assert(float32ToU64(0.0) == 0)
    Swag.assert(float32ToU64(123.75) == 123)
    Swag.assert(float32ToU64(9_223_371_487_098_961_920.0) == 0x7FFF_FF80_0000_0000)
    Swag.assert(float32ToU64(9_223_372_036_854_775_808.0) == 0x8000_0000_0000_0000)
    Swag.assert(float32ToU64(9_223_373_136_366_403_584.0) == 0x8000_0100_0000_0000)
    Swag.assert(float32ToU64(18_446_742_974_197_923_840.0) == 0xFFFF_FF00_0000_0000)
}

#test
{
    Swag.assert(float64ToU64(0.0) == 0)
    Swag.assert(float64ToU64(123.75) == 123)
    Swag.assert(float64ToU64(9_223_372_036_854_774_784.0) == 0x7FFF_FFFF_FFFF_FC00)
    Swag.assert(float64ToU64(9_223_372_036_854_775_808.0) == 0x8000_0000_0000_0000)
    Swag.assert(float64ToU64(9_223_372_036_854_777_856.0) == 0x8000_0000_0000_0800)
    Swag.assert(float64ToU64(18_446_744_073_709_549_568.0) == 0xFFFF_FFFF_FFFF_F800)
}

#test
{
    var a: s32 = -10
    takes_f32(a)
    takes_f64(a)
    Swag.assert(gFloatF32 == -10.0)
    Swag.assert(gFloatF64 == -10.0)
}

#test
{
    var a: s64 = -10
    takes_f64(a)
    Swag.assert(gFloatF64 == -10.0)
}

#test
{
    var a: u32 = 10
    takes_f32(a)
    takes_f64(a)
    Swag.assert(gFloatF32 == 10.0)
    Swag.assert(gFloatF64 == 10.0)
}

// The x64 float-to-integer conversion carries ONE width for both of its sides, so a
// conversion done at the source float's width truncates the result to that width. Every
// case below needs a destination wider than 'f32': at 32 bits a negative value reads back
// as its unsigned complement, and a value past the signed 32-bit range as the integer
// indefinite. All the constants are exact in both 'f32' and 'f64'.

#test
{
    gFloatF32 = -64.0
    gFloatF64 = -64.0
    Swag.assert(cast(s8) gFloatF32 == -64)
    Swag.assert(cast(s16) gFloatF32 == -64)
    Swag.assert(cast(s32) gFloatF32 == -64)
    Swag.assert(cast(s64) gFloatF32 == -64)
    Swag.assert(cast(s64) gFloatF64 == -64)
}

#test
{
    gFloatF32 = 3.0e9
    gFloatF64 = 3.0e9
    Swag.assert(cast(u32) gFloatF32 == 3_000_000_000)
    Swag.assert(cast(u64) gFloatF32 == 3_000_000_000)
    Swag.assert(cast(u32) gFloatF64 == 3_000_000_000)
    Swag.assert(cast(u64) gFloatF64 == 3_000_000_000)
}

#test
{
    gFloatF32 = -12_884_901_888.0
    gFloatF64 = -12_884_901_888.0
    Swag.assert(cast(s64) gFloatF32 == -12_884_901_888)
    Swag.assert(cast(s64) gFloatF64 == -12_884_901_888)
}
