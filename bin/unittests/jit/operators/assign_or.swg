#global private

#test
{
    func orEqU32()->u32
    {
        var v: u32 = 0x20_u32
        v |= 0x0A_u32
        return v
    }

    const V = #run orEqU32()
    #assert(#typeof(V) == u32)
    #assert(V == 42_u32)
}

#test
{
    func orEqU64()->u64
    {
        var v: u64 = 0x2_u64
        v |= 0x28_u64
        return v
    }

    const V = #run orEqU64()
    #assert(#typeof(V) == u64)
    #assert(V == 42_u64)
}
