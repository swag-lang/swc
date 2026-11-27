#global private

#test
{
    func andEqU32()->u32
    {
        var v: u32 = 0x3F_u32
        v &= 0x2A_u32
        return v
    }

    const V = #run andEqU32()
    #assert(#typeof(V) == u32)
    #assert(V == 42_u32)
}

#test
{
    func andEqU64()->u64
    {
        var v: u64 = 0xFFFF_u64
        v &= 42_u64
        return v
    }

    const V = #run andEqU64()
    #assert(#typeof(V) == u64)
    #assert(V == 42_u64)
}
