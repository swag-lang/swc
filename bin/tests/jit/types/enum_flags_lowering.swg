#global fileprivate // swc-option suite-jit

#[Swag.EnumFlags]
enum LowerFlags: u32
{
    A
    B
    C
    D
}

#test
{
    func lowerFlagsOrAnd()->bool
    {
        let v = LowerFlags.A | LowerFlags.C
        return (v & LowerFlags.A) != 0 and (v & LowerFlags.B) == 0 and (v & LowerFlags.C) != 0
    }

    const V = #run lowerFlagsOrAnd()
    #assert(V)
}

#test
{
    func lowerFlagsXor()->bool
    {
        let v0 = LowerFlags.A | LowerFlags.C
        let v1 = v0 ^ LowerFlags.C
        return (v1 & LowerFlags.C) == 0 and (v1 & LowerFlags.A) != 0
    }

    const V = #run lowerFlagsXor()
    #assert(V)
}

#test
{
    func lowerTypeInfoFlags()->bool
    {
        let t: typeinfo = #typeof(s32)
        let f = t.flags | .Nullable
        return (f & .Nullable) != 0
    }

    const V = #run lowerTypeInfoFlags()
    #assert(V)
}
