#global fileprivate

#test
{
    func shlEqU32()->u32
    {
        var v: u32 = 21'u32
        v <<= 1'u32
        return v
    }

    const V = #run shlEqU32()
    #assert(#typeof(V) == u32)
    #assert(V == 42'u32)
}

#test
{
    func shlEqU64()->u64
    {
        var v: u64 = 21'u64
        v <<= 1'u32
        return v
    }

    const V = #run shlEqU64()
    #assert(#typeof(V) == u64)
    #assert(V == 42'u64)
}
