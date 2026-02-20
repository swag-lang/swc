#global internal

enum CondEnum: u16
{
    A = 1
    B = 2
}

#test
{
    func ternaryInt(cond: bool, a: s32, b: s32)->s32
    {
        return cond ? a : b
    }

    const V0 = #run ternaryInt(true, 42, 10)
    const V1 = #run ternaryInt(false, 42, 10)
    #assert(#typeof(V0) == s32)
    #assert(V0 == 42)
    #assert(V1 == 10)
}

#test
{
    func ternaryMixedNumeric(cond: bool)->f64
    {
        return cond ? 42 : 1.5'f64
    }

    const V0 = #run ternaryMixedNumeric(true)
    const V1 = #run ternaryMixedNumeric(false)
    #assert(#typeof(V0) == f64)
    #assert(V0 == 42.0'f64)
    #assert(V1 == 1.5'f64)
}

#test
{
    func ternaryFloat(cond: bool)->f64
    {
        return cond ? 42.5'f64 : 1.25'f64
    }

    const V0 = #run ternaryFloat(true)
    const V1 = #run ternaryFloat(false)
    #assert(#typeof(V0) == f64)
    #assert(V0 == 42.5'f64)
    #assert(V1 == 1.25'f64)
}

#test
{
    func ternaryString(cond: bool)->string
    {
        return cond ? "left" : "right"
    }

    const V0 = #run ternaryString(true)
    const V1 = #run ternaryString(false)
    #assert(#typeof(V0) == string)
    #assert(V0 == "left")
    #assert(V1 == "right")
}

#test
{
    func ternaryEnum(cond: bool)->CondEnum
    {
        return cond ? CondEnum.A : CondEnum.B
    }

    const V0 = #run ternaryEnum(true)
    const V1 = #run ternaryEnum(false)
    #assert(#typeof(V0) == CondEnum)
    #assert(V0 == CondEnum.A)
    #assert(V1 == CondEnum.B)
}

#test
{
    func ternaryPointer(cond: bool, p0: *void, p1: *void)->*void
    {
        return cond ? p0 : p1
    }

    const A = cast(*void) 0x1234'u64
    const B = cast(*void) 0x5678'u64
    const V0 = #run ternaryPointer(true, A, B)
    const V1 = #run ternaryPointer(false, A, B)
    #assert(V0 == A)
    #assert(V1 == B)
}

#test
{
    func ternaryCondInt(cond: s32)->s32
    {
        return cond ? 11 : 22
    }

    const V0 = #run ternaryCondInt(1)
    const V1 = #run ternaryCondInt(0)
    #assert(V0 == 11)
    #assert(V1 == 22)
}

#test
{
    func ternaryCondPointer(cond: *void)->s32
    {
        return cond ? 7 : 9
    }

    const V0 = #run ternaryCondPointer(cast(*void) 0x1'u64)
    const V1 = #run ternaryCondPointer(null)
    #assert(V0 == 7)
    #assert(V1 == 9)
}

#test
{
    func ternaryBad(cond: bool)->s32
    {
        return cond ? 1 : "bad" // swc-expected-error {{sema_err_binary_operand_type}}
    }
}
