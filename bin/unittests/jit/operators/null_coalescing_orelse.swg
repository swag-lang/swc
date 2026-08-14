#global private

var GNullCoerc: s32 = 56

// 'orelse' only substitutes a MISSING value, so a zero substitution is written with the
// ternary. These keep the coverage of the zero-defaulting shapes at each scalar width.
#test
{
    func zeroFallbackU32(x: u32)->u32
    {
        return x != 0 ? x : 7'u32
    }

    const V0 = #run zeroFallbackU32(0'u32)
    const V1 = #run zeroFallbackU32(9'u32)
    #assert(V0 == 7'u32)
    #assert(V1 == 9'u32)
}

#test
{
    func zeroFallbackRune(x: rune)->rune
    {
        return x != cast(rune) 0'u32 ? x : 'A'rune
    }

    const V0 = #run zeroFallbackRune(cast(rune) 0'u32)
    const V1 = #run zeroFallbackRune('B'rune)
    #assert(V0 == 'A'rune)
    #assert(V1 == 'B'rune)
}

#test
{
    func zeroFallbackF32(x: f32)->f32
    {
        return x != 0.0'f32 ? x : 3.5'f32
    }

    const V0 = #run zeroFallbackF32(0.0'f32)
    const V1 = #run zeroFallbackF32(2.25'f32)
    #assert(V0 == 3.5'f32)
    #assert(V1 == 2.25'f32)
}

#test
{
    func nullStringFallback(value: #null string)->bool
    {
        let resolved = value orelse "fallback"
        return resolved == "fallback"
    }

    const V = #run nullStringFallback(null)
    #assert(V)
}

#test
{
    func nullPointerFallback(ptr: #null *s32)->s32
    {
        let fallback = cast(*s32) &GNullCoerc
        let resolved = ptr orelse fallback
        return resolved[]
    }

    const V = #run nullPointerFallback(null)
    #assert(V == 56)
}

#test
{
    func nonNullPointerWins()->bool
    {
        var x: u8    = 0
        var y: u8    = 0
        let ptr      = cast(*void) &x
        let fallback = cast(*void) &y
        let resolved = ptr orelse fallback
        return resolved == ptr and resolved != fallback
    }

    const V = #run nonNullPointerWins()
    #assert(V)
}
