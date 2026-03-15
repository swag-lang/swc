#global fileprivate

#test
{
    func modEqS32()->s32
    {
        var v: s32 = 100
        v %= 58
        return v
    }

    const V = #run modEqS32()
    #assert(#typeof(V) == s32)
    #assert(V == 42)
}

#test
{
    func modEqU64()->u64
    {
        var v: u64 = 1000'u64
        v %= 479'u64
        return v
    }

    const V = #run modEqU64()
    #assert(#typeof(V) == u64)
    #assert(V == 42'u64)
}
