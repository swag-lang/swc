#global private

#test
{
    func postfixDerefRead()->s32
    {
        var value = 42's32
        let p     = &value
        return p[]
    }
    const V = #run postfixDerefRead()
    #assert(V == 42)
}

#test
{
    func postfixDerefWrite()->s32
    {
        var value = 1's32
        let p     = &value
        p[] = 7
        return value
    }
    const V = #run postfixDerefWrite()
    #assert(V == 7)
}

#test
{
    func postfixDerefChain()->s32
    {
        var value = 5's32
        var p     = &value
        var pp    = &p
        pp[][] += 4
        return pp[][]
    }
    const V = #run postfixDerefChain()
    #assert(V == 9)
}

#test
{
    func derefCastRead()->s32
    {
        var bits = 0xFFFF_FFFF'u32
        let p    = &bits
        return p[as s32]
    }
    const V = #run derefCastRead()
    #assert(V == -1)
}

#test
{
    func derefCastWrite()->u32
    {
        var value = 0x0102_0304'u32
        let p     = &value
        p[as u8] = 0xFF
        return value
    }
    const V = #run derefCastWrite()
    #assert(V == 0x0102_03FF'u32)
}
