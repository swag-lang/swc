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
