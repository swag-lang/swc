#global internal

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

#test
{
    func variadicTyped(values: s32...)->s32 { return values[0] + values[1] + values[2] + values[3] }
    const V0 = #run variadicTyped(1, 2, 3, 4)
    #assert(V0 == 10)
}

#test
{
    func variadicTyped(values: s64...)->s64 { return values[0] + values[1] + values[2] + values[3] }
    const V0 = #run variadicTyped(10's64, 20's64, 30's64, 40's64)
    #assert(#typeof(V0) == s64)
    #assert(V0 == 100's64)
}

#test
{
    func variadicTypedWithHead(a: s64, values: s64...)->s64 { return a + values[0] + values[1] }
    const V0 = #run variadicTypedWithHead(100's64, 7's64, 8's64)
    #assert(#typeof(V0) == s64)
    #assert(V0 == 115's64)
}

#test
{
    func variadicTyped(values: u32...)->u32 { return values[0] + values[1] + values[2] + values[3] }
    const V0 = #run variadicTyped(1'u32, 2'u32, 3'u32, 4'u32)
    #assert(#typeof(V0) == u32)
    #assert(V0 == 10'u32)
}

#test
{
    func variadicTypedWithHead(a: u32, values: u32...)->u32 { return a + values[0] + values[1] }
    const V0 = #run variadicTypedWithHead(50'u32, 60'u32, 70'u32)
    #assert(#typeof(V0) == u32)
    #assert(V0 == 180'u32)
}

#test
{
    func variadicTyped(values: f32...)->f32 { return values[0] + values[1] + values[2] }
    const V0 = #run variadicTyped(1.5'f32, 2.0'f32, 3.25'f32)
    #assert(#typeof(V0) == f32)
    #assert(V0 == 6.75'f32)
}

#test
{
    func variadicTypedWithHead(a: f32, values: f32...)->f32 { return a + values[0] + values[1] }
    const V0 = #run variadicTypedWithHead(4.0'f32, 0.25'f32, 1.75'f32)
    #assert(#typeof(V0) == f32)
    #assert(V0 == 6.0'f32)
}

#test
{
    func variadicTyped(values: f64...)->f64 { return values[0] + values[1] + values[2] + values[3] }
    const V0 = #run variadicTyped(1.0'f64, 2.0'f64, 3.0'f64, 4.0'f64)
    #assert(#typeof(V0) == f64)
    #assert(V0 == 10.0'f64)
}

#test
{
    func variadicTypedWithHead(a: f64, values: f64...)->f64 { return a + values[0] + values[1] }
    const V0 = #run variadicTypedWithHead(10.0'f64, 0.5'f64, 1.25'f64)
    #assert(#typeof(V0) == f64)
    #assert(V0 == 11.75'f64)
}

#test
{
    func variadicTyped(values: bool...)->s32 { return cast(s32) values[0] + cast(s32) values[1] + cast(s32) values[2] + cast(s32) values[3] }
    const V0 = #run variadicTyped(true, false, true, true)
    #assert(V0 == 3)
}

#test
{
    func variadicTypedWithHead(a: bool, values: bool...)->s32 { return cast(s32) a + cast(s32) values[0] + cast(s32) values[1] }
    const V0 = #run variadicTypedWithHead(false, true, true)
    #assert(V0 == 2)
}

#test
{
    func variadicTyped(values: rune...)->s32 { return cast(s32) values[0] + cast(s32) values[1] + cast(s32) values[2] }
    const V0 = #run variadicTyped('A', 'B', 'C')
    #assert(V0 == 198)
}

#test
{
    func variadicTypedWithHead(a: rune, values: rune...)->s32 { return cast(s32) a + cast(s32) values[0] + cast(s32) values[1] }
    const V0 = #run variadicTypedWithHead('a', 'b', 'c')
    #assert(V0 == 294)
}

#test
{
    func variadicTypedWithHead(a: rune, values: rune...)->u64 { return @countof(values) }
    const V0 = #run variadicTypedWithHead('a', 'b', 'c')
    #assert(V0 == 2)
}

#test
{
    func variadicTyped(values: string...)->string { return values[0] }
    const V0 = #run variadicTyped("ab")
    #assert(V0 == "ab")
}

#test
{
    func variadicTyped(values: string...)->u8 { return values[0][0] + values[1][0] + values[2][0] }
    const V0 = #run variadicTyped("ab", "cd", "ef")
    #assert(#typeof(V0) == u8)
    #assert(V0 == 41'u8)
}

#test
{
    func variadicTypedWithHead(a: string, values: string...)->u8 { return a[0] + values[0][0] + values[1][0] }
    const V0 = #run variadicTypedWithHead("Az", "By", "Cx")
    #assert(#typeof(V0) == u8)
    #assert(V0 == 198'u8)
}
