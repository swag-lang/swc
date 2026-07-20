#global private

var GNullOrelse: s32 = 56

func zeroFallbackU32(x: u32)->u32
{
    return x orelse 7'u32
}

func zeroFallbackRune(x: rune)->rune
{
    return x orelse 'A''rune
}

func zeroFallbackF32(x: f32)->f32
{
    return x orelse 3.5'f32
}

func nullStringFallback(value: #null string)->string
{
    return value orelse "fallback"
}

func nullPointerFallback(ptr: #null *s32)->s32
{
    let fallback = cast(*s32) &GNullOrelse
    let resolved = ptr orelse fallback
    return dref resolved
}

func nonNullPointerWins()->bool
{
    var x: u8 = 0
    var y: u8 = 0
    let ptr = cast(*void) &x
    let fallback = cast(*void) &y
    let resolved = ptr orelse fallback
    return resolved == ptr and resolved != fallback
}

#test
{
    @assert(zeroFallbackU32(0'u32) == 7'u32)
    @assert(zeroFallbackU32(9'u32) == 9'u32)
    @assert(zeroFallbackRune(cast(rune) 0'u32) == 'A''rune)
    @assert(zeroFallbackRune('B''rune) == 'B''rune)
    @assert(zeroFallbackF32(0.0'f32) == 3.5'f32)
    @assert(zeroFallbackF32(2.25'f32) == 2.25'f32)
}

#test
{
    @assert(nullStringFallback(null) == "fallback")
    @assert(nullStringFallback("ok") == "ok")
    @assert(nullPointerFallback(null) == 56)
    @assert(nonNullPointerWins())
}
