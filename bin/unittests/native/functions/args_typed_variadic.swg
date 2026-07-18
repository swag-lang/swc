#global private
#global #[Swag.ExplicitNullability]

struct TypedVariadicPair
{
    a: s32
    b: s32
}

alias TypedVariadicAlias = s32

#[Swag.Strict]
alias TypedVariadicStrictF32 = f32

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

func variadicTypedString(a: #nonull string, values: #nonull string...)->u8
{
    return a[0] + values[0][0] + values[1][0]
}

func variadicTypedPair(a: s32, values: TypedVariadicPair...)->s32
{
    return a + values[0].a + values[0].b + values[1].a + values[1].b
}

func variadicTypedForwardInner(values: s32...)->s32
{
    var acc: s32 = 0
    for value in values do
        acc += value
    return acc
}

func variadicTypedForward(values: s32...)->s32
{
    return variadicTypedForwardInner(values)
}

func variadicTypedAliasForwardInner(values: s32...)->s32
{
    var acc: s32 = 0
    for value in values do
        acc += value
    return acc
}

func variadicTypedAliasForward(values: TypedVariadicAlias...)->s32
{
    return variadicTypedAliasForwardInner(values)
}

func variadicTypedAliasInner(values: TypedVariadicAlias...)->s32
{
    var acc: s32 = 0
    for value in values do
        acc += value
    return acc
}

func variadicTypedBaseForwardToAlias(values: s32...)->s32
{
    return variadicTypedAliasInner(values)
}

func variadicTypedPairForwardInner(values: TypedVariadicPair...)->s32
{
    return values[0].a + values[0].b + values[1].a + values[1].b
}

func variadicTypedPairForward(values: TypedVariadicPair...)->s32
{
    return variadicTypedPairForwardInner(values)
}

func variadicTypedStrictF32(values: TypedVariadicStrictF32...)->f32
{
    return cast(f32) values[0] + cast(f32) values[1]
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
    @assert(variadicTypedStrictF32(cast(TypedVariadicStrictF32) 1.5, cast(TypedVariadicStrictF32) 2.5) == 4.0'f32)
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

#test
{
    const p0: TypedVariadicPair = {a: 2, b: 3}
    const p1: TypedVariadicPair = {a: 5, b: 7}
    @assert(variadicTypedForward(10, 20, 30) == 60)
    @assert(variadicTypedAliasForward(10, 20, 30) == 60)
    @assert(variadicTypedBaseForwardToAlias(10, 20, 30) == 60)
    @assert(variadicTypedPairForward(p0, p1) == 17)
}
