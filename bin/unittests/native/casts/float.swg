#global private

var gFloatF32: f32
var gFloatF64: f64
func takes_f32(v: f32) { gFloatF32 = v }
func takes_f64(v: f64) { gFloatF64 = v }

#test
{
    var a: s32 = -10
    takes_f32(a)
    takes_f64(a)
    @assert(gFloatF32 == -10.0)
    @assert(gFloatF64 == -10.0)
}

#test
{
    var a: s64 = -10
    takes_f64(a)
    @assert(gFloatF64 == -10.0)
}

#test
{
    var a: u32 = 10
    takes_f32(a)
    takes_f64(a)
    @assert(gFloatF32 == 10.0)
    @assert(gFloatF64 == 10.0)
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
    @assert(cast(s8) gFloatF32 == -64)
    @assert(cast(s16) gFloatF32 == -64)
    @assert(cast(s32) gFloatF32 == -64)
    @assert(cast(s64) gFloatF32 == -64)
    @assert(cast(s64) gFloatF64 == -64)
}

#test
{
    gFloatF32 = 3.0e9
    gFloatF64 = 3.0e9
    @assert(cast(u32) gFloatF32 == 3_000_000_000)
    @assert(cast(u64) gFloatF32 == 3_000_000_000)
    @assert(cast(u32) gFloatF64 == 3_000_000_000)
    @assert(cast(u64) gFloatF64 == 3_000_000_000)
}

#test
{
    gFloatF32 = -12_884_901_888.0
    gFloatF64 = -12_884_901_888.0
    @assert(cast(s64) gFloatF32 == -12_884_901_888)
    @assert(cast(s64) gFloatF64 == -12_884_901_888)
}
