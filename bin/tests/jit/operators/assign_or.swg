#global fileprivate // swc-option suite-jit

#test
{
    func orEqU32()->u32
    {
        var v: u32 = 0x20'u32
        v |= 0x0A'u32
        return v
    }

    const V = #run orEqU32()
    #assert(#typeof(V) == u32)
    #assert(V == 42'u32)
}

#test
{
    func orEqU64()->u64
    {
        var v: u64 = 0x2'u64
        v |= 0x28'u64
        return v
    }

    const V = #run orEqU64()
    #assert(#typeof(V) == u64)
    #assert(V == 42'u64)
}
