#global internal

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
    func ternaryBad(cond: bool)->s32
    {
        return cond ? 1 : "bad" // swc-expected-error {{sema_err_binary_operand_type}}
    }
}
