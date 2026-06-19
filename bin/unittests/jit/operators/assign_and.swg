#global fileprivate

#test
{
    func andEqU32()->u32
    {
        var v: u32 = 0x3F'u32
        v &= 0x2A'u32
        return v
    }

    const V = #run andEqU32()
    #assert(#typeof(V) == u32)
    #assert(V == 42'u32)
}

#test
{
    func andEqU64()->u64
    {
        var v: u64 = 0xFFFF'u64
        v &= 42'u64
        return v
    }

    const V = #run andEqU64()
    #assert(#typeof(V) == u64)
    #assert(V == 42'u64)
}
