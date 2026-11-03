#global private

var GNullOrelse: s32 = 56

func zeroFallbackU32(x: u32)->u32
{
    return x != 0 ? x : 7'u32
}

func zeroFallbackRune(x: rune)->rune
{
    return x != cast(rune, 0'u32) ? x : 'A'rune
}

func zeroFallbackF32(x: f32)->f32
{
    return x != 0.0'f32 ? x : 3.5'f32
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
    Swag.require(zeroFallbackU32(0'u32) == 7'u32)
    Swag.require(zeroFallbackU32(9'u32) == 9'u32)
    Swag.require(zeroFallbackRune(cast(rune, 0'u32)) == 'A'rune)
    Swag.require(zeroFallbackRune('B'rune) == 'B'rune)
    Swag.require(zeroFallbackF32(0.0'f32) == 3.5'f32)
    Swag.require(zeroFallbackF32(2.25'f32) == 2.25'f32)
}

#test
{
    Swag.require(nullStringFallback(null) == "fallback")
    Swag.require(nullStringFallback("ok") == "ok")
    Swag.require(nullPointerFallback(null) == 56)
    Swag.require(nonNullPointerWins())
}
