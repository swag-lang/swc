#global fileprivate // swc-option suite-test

func variadicAnyOnly(values: ...)->u64
{
    return @countof(values)
}

func variadicAnyWithHead(a: s32, values: ...)->s32
{
    return a + cast(s32) @countof(values)
}

func variadicAnyS32(values: ...)->s32
{
    let p0 = cast(*s32) @dataof(values[0])
    let p1 = cast(*s32) @dataof(values[1])
    let p2 = cast(*s32) @dataof(values[2])
    let p3 = cast(*s32) @dataof(values[3])
    return dref p0 + dref p1 + dref p2 + dref p3
}

func variadicAnyF64(a: f64, values: ...)->f64
{
    let p0 = cast(*f64) @dataof(values[0])
    let p1 = cast(*f64) @dataof(values[1])
    return a + dref p0 + dref p1
}

func variadicAnyBool(a: bool, values: ...)->s32
{
    let p0 = cast(*bool) @dataof(values[0])
    let p1 = cast(*bool) @dataof(values[1])
    return cast(s32) a + cast(s32) dref p0 + cast(s32) dref p1
}

func variadicAnyRune(a: rune, values: ...)->s32
{
    let p0 = cast(*rune) @dataof(values[0])
    let p1 = cast(*rune) @dataof(values[1])
    return cast(s32) a + cast(s32) dref p0 + cast(s32) dref p1
}

func variadicAnyString(values: ...)->u8
{
    let s0 = cast(string) values[0]
    let s1 = cast(string) values[1]
    let s2 = cast(string) values[2]
    return s0[0] + s1[0] + s2[0]
}

#test
{
    @assert(variadicAnyOnly() == 0)
    @assert(variadicAnyOnly(1, 2, 3, 4) == 4)
    @assert(variadicAnyWithHead(42) == 42)
    @assert(variadicAnyWithHead(42, "x", 1, false) == 45)
}

#test
{
    @assert(variadicAnyS32(1's32, 2's32, 3's32, 4's32) == 10)
    @assert(variadicAnyF64(10.0'f64, 0.5'f64, 1.25'f64) == 11.75'f64)
    @assert(variadicAnyBool(false, true, true) == 2)
    @assert(variadicAnyRune('a', 'b', 'c') == 294)
    @assert(variadicAnyString("ab", "cd", "ef") == 41'u8)
}
