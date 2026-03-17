#global fileprivate // 

struct TypedVariadicPair
{
    a: s32
    b: s32
}

func variadicTypedCount(values: s32...)->u64
{
    return @countof(values)
}

func variadicTypedSum(values: s32...)->s32
{
    return values[0] + values[1] + values[2] + values[3]
}

func variadicTypedHead(a: s32, values: s32...)->s32
{
    return a + values[0] + values[1]
}

func variadicTypedF64(values: f64...)->f64
{
    return values[0] + values[1] + values[2] + values[3]
}

func variadicTypedBool(values: bool...)->s32
{
    return cast(s32) values[0] + cast(s32) values[1] + cast(s32) values[2] + cast(s32) values[3]
}

func variadicTypedRune(a: rune, values: rune...)->s32
{
    return cast(s32) a + cast(s32) values[0] + cast(s32) values[1]
}

func variadicTypedString(a: string, values: string...)->u8
{
    return a[0] + values[0][0] + values[1][0]
}

func variadicTypedPair(a: s32, values: TypedVariadicPair...)->s32
{
    return a + values[0].a + values[0].b + values[1].a + values[1].b
}

#test
{
    @assert(variadicTypedCount() == 0)
    @assert(variadicTypedCount(1, 2, 3, 4) == 4)
    @assert(variadicTypedSum(1, 2, 3, 4) == 10)
    @assert(variadicTypedHead(100, 7, 8) == 115)
}

#test
{
    @assert(variadicTypedF64(1.0'f64, 2.0'f64, 3.0'f64, 4.0'f64) == 10.0'f64)
    @assert(variadicTypedBool(true, false, true, true) == 3)
    @assert(variadicTypedRune('a', 'b', 'c') == 294)
    @assert(variadicTypedString("Az", "By", "Cx") == 198'u8)
}

#test
{
    const p0: TypedVariadicPair = {a: 2, b: 3}
    const p1: TypedVariadicPair = {a: 5, b: 7}
    @assert(variadicTypedPair(1, p0, p1) == 18)
}
