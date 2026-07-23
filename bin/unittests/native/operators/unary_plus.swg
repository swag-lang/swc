#global private

#[Swag.Strict]
alias UnaryPlusStrictS32 = s32

#[Swag.Strict]
alias UnaryPlusStrictF32 = f32

func unaryPlusU32(a: u32)->u32
{
    return +a
}

func unaryPlusF64(a: f64)->f64
{
    return +a
}

func unaryPlusU64(a: u64)->u64
{
    return +a
}

func unaryPlusS32(a: s32)->s32
{
    return +a
}

func unaryPlusRune(a: rune)->rune
{
    return +a
}

func unaryPlusChain(a: f32)->f32
{
    return +(+a)
}

func unaryPlusStrictS32(a: UnaryPlusStrictS32)->UnaryPlusStrictS32
{
    return +a
}

func unaryPlusStrictF32(a: UnaryPlusStrictF32)->UnaryPlusStrictF32
{
    return +a
}

#test
{
    let v0 = unaryPlusU32(42'u32)
    let v1 = unaryPlusF64(42.5'f64)
    let v2 = unaryPlusU64(42'u64)
    let v3 = unaryPlusS32(-42)
    let v4 = unaryPlusRune('A''rune)
    let v5 = unaryPlusChain(42.5'f32)

    #assert(#typeof(v0) == u32)
    #assert(#typeof(v1) == f64)
    #assert(#typeof(v2) == u64)
    #assert(#typeof(v3) == s32)
    #assert(#typeof(v4) == rune)
    #assert(#typeof(v5) == f32)

    @assert(v0 == 42'u32)
    @assert(v1 == 42.5'f64)
    @assert(v2 == 42'u64)
    @assert(v3 == -42)
    @assert(v4 == 'A''rune)
    @assert(v5 == 42.5'f32)
}

#test
{
    let runtimeInt = unaryPlusStrictS32(cast(UnaryPlusStrictS32) -42)
    let runtimeFloat = unaryPlusStrictF32(cast(UnaryPlusStrictF32) 42.5'f32)
    const constantInt   = +cast(UnaryPlusStrictS32) -42
    const constantFloat = +cast(UnaryPlusStrictF32) 42.5'f32

    #assert(#typeof(runtimeInt) == UnaryPlusStrictS32)
    #assert(#typeof(runtimeFloat) == UnaryPlusStrictF32)
    #assert(#typeof(constantInt) == UnaryPlusStrictS32)
    #assert(#typeof(constantFloat) == UnaryPlusStrictF32)

    @assert(runtimeInt == cast(UnaryPlusStrictS32) -42)
    @assert(runtimeFloat == cast(UnaryPlusStrictF32) 42.5'f32)
    @assert(constantInt == cast(UnaryPlusStrictS32) -42)
    @assert(constantFloat == cast(UnaryPlusStrictF32) 42.5'f32)
}
