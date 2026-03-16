#global fileprivate // swc-option suite-jit

#test
{
    func shrEqU32()->u32
    {
        var v: u32 = 168'u32
        v >>= 2'u32
        return v
    }

    const V = #run shrEqU32()
    #assert(#typeof(V) == u32)
    #assert(V == 42'u32)
}

#test
{
    func shrEqS32()->s32
    {
        var v: s32 = -84
        v >>= 1
        return v
    }

    const V = #run shrEqS32()
    #assert(#typeof(V) == s32)
    #assert(V == -42)
}
