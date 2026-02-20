#global internal

// #test
// {
//     func variadicAnyOnly(values: ...)->s32 { return 77 }
//     const V0 = #run variadicAnyOnly()
//     const V1 = #run variadicAnyOnly(1, 2, 3)
//     const V2 = #run variadicAnyOnly("a", true, 12.5'f64)
//     #assert(V0 == 77)
//     #assert(V1 == 77)
//     #assert(V2 == 77)
// }
//
// #test
// {
//     func variadicAnyWithHead(a: s32, values: ...)->s32 { return a }
//     const V0 = #run variadicAnyWithHead(42)
//     const V1 = #run variadicAnyWithHead(42, "x", 1, false)
//     #assert(V0 == 42)
//     #assert(V1 == 42)
// }

#test
{
    func variadicTyped(values: s32...)->s32 { return 78 }
    const V0 = #run variadicTyped()
    const V1 = #run variadicTyped(1, 2, 3, 4)
    #assert(V0 == 78)
    #assert(V1 == 78)
}

#test
{
    func variadicTypedWithHead(a: s32, values: s32...)->s32 { return a }
    const V0 = #run variadicTypedWithHead(79)
    const V1 = #run variadicTypedWithHead(79, 10, 20, 30)
    #assert(V0 == 79)
    #assert(V1 == 79)
}

// #test
// {
//     func variadicHeadTypeErr(a: s32, values: ...)->s32 { return a }
//     const V = #run variadicHeadTypeErr("bad")
// }
//
// #test
// {
//     func variadicTypedArgTypeErr(values: s32...)->s32 { return 0 }
//     const V = #run variadicTypedArgTypeErr(1, "bad", 3)
// }
//
// #test
// {
//     func variadicHeadMissing(a: s32, values: ...)->s32 { return a }
//     const V = #run variadicHeadMissing()
// }
