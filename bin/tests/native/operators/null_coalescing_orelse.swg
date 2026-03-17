#global fileprivate // 

var GNullOrelse: s32 = 56

func zeroFallbackU32(x: u32)->u32
{
    return x orelse 7'u32
}

func zeroFallbackRune(x: rune)->rune
{
    return x orelse 'A''rune
}

func nullStringFallback(value: string)->string
{
    return value orelse "fallback"
}

func nullPointerFallback(ptr: *s32)->s32
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
}

#test
{
    @assert(nullStringFallback(null) == "fallback")
    @assert(nullStringFallback("ok") == "ok")
    @assert(nullPointerFallback(null) == 56)
    @assert(nonNullPointerWins())
}
