#global fileprivate // swc-option suite-test

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

func unaryPlusChain(a: f32)->f32
{
    return +(+a)
}

#test
{
    let v0 = unaryPlusU32(42'u32)
    let v1 = unaryPlusF64(42.5'f64)
    let v2 = unaryPlusU64(42'u64)
    let v3 = unaryPlusChain(42.5'f32)

    #assert(#typeof(v0) == u32)
    #assert(#typeof(v1) == f64)
    #assert(#typeof(v2) == u64)
    #assert(#typeof(v3) == f32)

    @assert(v0 == 42'u32)
    @assert(v1 == 42.5'f64)
    @assert(v2 == 42'u64)
    @assert(v3 == 42.5'f32)
}
