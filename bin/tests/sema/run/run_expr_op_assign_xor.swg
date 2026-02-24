#global internal

#test
{
    func xorEqU32()->u32
    {
        var v: u32 = 0x3F'u32
        v ^= 0x15'u32
        return v
    }

    const V = #run xorEqU32()
    #assert(#typeof(V) == u32)
    #assert(V == 42'u32)
}

#test
{
    func xorEqU64()->u64
    {
        var v: u64 = 0xFFFF'u64
        v ^= 0xFFD5'u64
        return v
    }

    const V = #run xorEqU64()
    #assert(#typeof(V) == u64)
    #assert(V == 42'u64)
}
