#global fileprivate // swc-option suite-test

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
