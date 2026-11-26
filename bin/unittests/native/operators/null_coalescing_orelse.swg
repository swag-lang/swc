#global private

var GNullOrelse: s32 = 56

func zeroFallbackU32(x: u32)->u32
{
    return x != 0 ? x : 7_u32
}

func zeroFallbackRune(x: rune)->rune
{
    return x != cast(rune, 0_u32) ? x : 'A'_rune
}

func zeroFallbackF32(x: f32)->f32
{
    return x != 0.0_f32 ? x : 3.5_f32
}

func nullStringFallback(value: string?)->string
{
    return value orelse "fallback"
}

func nullPointerFallback(ptr: *s32?)->s32
{
    let fallback = cast(*s32, &GNullOrelse)
    let resolved = ptr orelse fallback
    return resolved[]
}

func nonNullPointerWins()->bool
{
    var x: u8    = 0
    var y: u8    = 0
    let ptr      = cast(*void, &x)
    let fallback = cast(*void, &y)
    let resolved = ptr orelse fallback
    return resolved == ptr and resolved != fallback
}

#test
{
    Swag.require(zeroFallbackU32(0_u32) == 7_u32)
    Swag.require(zeroFallbackU32(9_u32) == 9_u32)
    Swag.require(zeroFallbackRune(cast(rune, 0_u32)) == 'A'_rune)
    Swag.require(zeroFallbackRune('B'_rune) == 'B'_rune)
    Swag.require(zeroFallbackF32(0.0_f32) == 3.5_f32)
    Swag.require(zeroFallbackF32(2.25_f32) == 2.25_f32)
}

#test
{
    Swag.require(nullStringFallback(null) == "fallback")
    Swag.require(nullStringFallback("ok") == "ok")
    Swag.require(nullPointerFallback(null) == 56)
    Swag.require(nonNullPointerWins())
}
