#global private

#[Swag.Strict]
alias UnaryMinusStrictS32 = s32

#[Swag.Strict]
alias UnaryMinusStrictF32 = f32

func unaryMinusS32(a: s32)->s32
{
    return -a
}

func unaryMinusF64(a: f64)->f64
{
    return -a
}

func unaryMinusS64(a: s64)->s64
{
    return -a
}

func unaryMinusChain(a: s32)->s32
{
    return -(-a)
}

func unaryMinusStrictS32(a: UnaryMinusStrictS32)->UnaryMinusStrictS32
{
    return -a
}

func unaryMinusStrictF32(a: UnaryMinusStrictF32)->UnaryMinusStrictF32
{
    return -a
}

// Unary minus on s32, f64, s64, and double negation
#test
{
    let v0 = unaryMinusS32(42)
    let v1 = unaryMinusF64(42.5'f64)
    let v2 = unaryMinusS64(42's64)
    let v3 = unaryMinusChain(42)

    #assert(#typeof(v0) == s32)
    #assert(#typeof(v1) == f64)
    #assert(#typeof(v2) == s64)
    #assert(#typeof(v3) == s32)

    @assert(v0 == -42)
    @assert(v1 == -42.5'f64)
    @assert(v2 == -42's64)
    @assert(v3 == 42)
}

#test
{
    let runtimeValue = unaryMinusStrictS32(cast(UnaryMinusStrictS32) 42)
    const constantValue = -cast(UnaryMinusStrictS32) 42

    #assert(#typeof(runtimeValue) == UnaryMinusStrictS32)
    #assert(#typeof(constantValue) == UnaryMinusStrictS32)

    @assert(runtimeValue == cast(UnaryMinusStrictS32) -42)
    @assert(constantValue == cast(UnaryMinusStrictS32) -42)
}

#test
{
    let runtimeValue = unaryMinusStrictF32(cast(UnaryMinusStrictF32) 1.5'f32)
    const constantValue = -cast(UnaryMinusStrictF32) 1.5'f32

    #assert(#typeof(runtimeValue) == UnaryMinusStrictF32)
    #assert(#typeof(constantValue) == UnaryMinusStrictF32)

    @assert(runtimeValue == cast(UnaryMinusStrictF32) -1.5'f32)
    @assert(constantValue == cast(UnaryMinusStrictF32) -1.5'f32)
}
