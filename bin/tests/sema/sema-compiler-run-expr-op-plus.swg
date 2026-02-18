#global internal

#test
{
    func add(a: s32, b: s32)->s32 { return a + b }
    const V = #run add(39, 3)
    #assert(#typeof(V) == s32)
    #assert(V == 42)
}

#test
{
    func add(a: f64, b: f64)->f64 { return a + b }
    const V = #run add(1.5'f64, 2.25'f64)
    #assert(#typeof(V) == f64)
    #assert(V == 3.75'f64)
}

#test
{
    func add(a: s64, b: s64)->s64 { return a + b }
    const V = #run add(10000000000's64, 7's64)
    #assert(#typeof(V) == s64)
    #assert(V == 10000000007's64)
}

#test
{
    func add(a: f32, b: f32)->f32 { return a + b }
    const V = #run add(1.25'f32, 2.5'f32)
    #assert(#typeof(V) == f32)
    #assert(V == 3.75'f32)
}

#test
{
    func add(a: f64, b: f64)->f64 { return a + b }
    const V = #run add(40, 2.5'f64)
    #assert(#typeof(V) == f64)
    #assert(V == 42.5'f64)
}

#test
{
    func addManyInts(
        a0: s32, a1: s32, a2: s32, a3: s32,
        a4: s32, a5: s32, a6: s32, a7: s32,
        a8: s32, a9: s32, a10: s32, a11: s32)->s32
    {
        return a0 + a11
    }

    const V = #run addManyInts(40, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 2)
    #assert(#typeof(V) == s32)
    #assert(V == 42)
}

#test
{
    func addChainInt(a: s32, b: s32, c: s32, d: s32, e: s32)->s32 { return a + b + c + d + e }
    const V = #run addChainInt(30, 5, 4, 2, 1)
    #assert(#typeof(V) == s32)
    #assert(V == 42)
}

#test
{
    #[Swag.PrintMicro, Swag.Optimize(.O0)]
    func addChainFloat(a: f64, b: f64, c: f64, d: f64)->f64 { return a + b + c + d }
    const V = #run addChainFloat(10.0'f64, 20.5'f64, 5.25'f64, 6.25'f64)
    #assert(#typeof(V) == f64)
    #assert(V == 42.0'f64)
}

#test
{
    #[Swag.Optimize(.NotAnOptLevel)] // swc-expected-error {{sema_err_auto_scope_missing_enum_value}}
    func addAttrBad(a: s32, b: s32)->s32 { return a + b }
}

//#test
//{
//    func addManyMixed(
//        a0: s32, a1: f32, a2: s64, a3: f64, a4: u32, a5: f32,
//        a6: s32, a7: f64, a8: u16, a9: f32, a10: s8, a11: f64)->f64
//    {
//        return cast(f64) a0 + cast(f64) a1 + cast(f64) a2 + a3 + cast(f64) a4 + cast(f64) a5 +
//               cast(f64) a6 + a7 + cast(f64) a8 + cast(f64) a9 + cast(f64) a10 + a11
//    }
//
//    const V = #run addManyMixed(1, 2.5'f32, 3's64, 4.0'f64, 5'u32, 6.0'f32, 7, 8.0'f64, 2'u16, 1.0'f32, 2's8, 0.5'f64)
//    #assert(#typeof(V) == f64)
//    #assert(V == 42.5'f64)
//}
