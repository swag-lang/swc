#global internal

struct TypedVariadicPair
{
    a: s32
    b: s32
}

struct TypedVariadicPayload
{
    arr: [3] s32
    flag: bool
    tag: u8
}

enum TypedVariadicKind: u16
{
    A = 11
    B = 29
}

alias TypedVariadicAlias = s32

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

#test
{
    func variadicTyped(values: TypedVariadicAlias...)->s32
    {
        return values[0] + values[1] + values[2]
    }

    const V0 = #run variadicTyped(10, 20, 30)
    #assert(V0 == 60)
}

#test
{
    func variadicTyped(values: s32...)->bool
    {
        return #typeof(values[0]) == s32 and #typeof(values[1]) == s32 and #typeof(values[2]) == s32
    }

    const V0 = #run variadicTyped(4, 5, 6)
    #assert(V0)
}

#test
{
    func variadicTypedWithHead(a: s32, values: TypedVariadicPair...)->s32
    {
        return a + values[0].a + values[0].b + values[1].a + values[1].b
    }

    const p0: TypedVariadicPair = {a: 2, b: 3}
    const p1: TypedVariadicPair = {a: 5, b: 7}
    const V0 = #run variadicTypedWithHead(1, p0, p1)
    #assert(V0 == 18)
}

#test
{
    func variadicTyped(values: TypedVariadicPair...)->s32
    {
        return values[0].a + values[0].b + values[1].a + values[1].b
    }

    const p0: TypedVariadicPair = {a: 2, b: 3}
    const p1: TypedVariadicPair = {a: 5, b: 7}
    const V0 = #run variadicTyped(p0, p1)
    #assert(V0 == 17)
}

#test
{
    func variadicTyped(values: [4] s32...)->s32
    {
        return values[0][0] + values[0][3] + values[1][1] + values[1][2]
    }

    const a0: [4] s32 = [1, 2, 3, 4]
    const a1: [4] s32 = [10, 20, 30, 40]
    const V0 = #run variadicTyped(a0, a1)
    #assert(V0 == 55)
}

#test
{
    func variadicTyped(values: TypedVariadicKind...)->u16
    {
        return cast(u16) values[0] + cast(u16) values[1]
    }

    const V0 = #run variadicTyped(TypedVariadicKind.A, TypedVariadicKind.B)
    #assert(#typeof(V0) == u16)
    #assert(V0 == 40'u16)
}

#test
{
    func variadicTyped(values: TypedVariadicPayload...)->u64
    {
        return cast(u64) values[0].arr[1] + cast(u64) values[0].flag + cast(u64) values[0].tag + cast(u64) values[1].arr[0] + cast(u64) values[1].tag
    }

    const v0: TypedVariadicPayload = {arr: [9, 8, 7], flag: true, tag: 5'u8}
    const v1: TypedVariadicPayload = {arr: [3, 2, 1], flag: false, tag: 4'u8}
    const V0 = #run variadicTyped(v0, v1)
    #assert(#typeof(V0) == u64)
    #assert(V0 == 21'u64)
}

#test
{
    func variadicTyped(values: *void...)->bool
    {
        return values[0] == cast(*void) 0x1234'u64 and values[1] == null
    }

    const V0 = #run variadicTyped(cast(*void) 0x1234'u64, null)
    #assert(V0)
}

#test
{
    func variadicTyped(values: TypedVariadicKind...)->bool
    {
        return #typeof(values[0]) == TypedVariadicKind and #typeof(values[1]) == TypedVariadicKind
    }

    const V0 = #run variadicTyped(TypedVariadicKind.A, TypedVariadicKind.B)
    #assert(V0)
}
