#global internal

struct VariadicPair
{
    a: s32
    b: s32
}

struct VariadicPayload
{
    arr: [3] s32
    flag: bool
    tag: u8
}

enum VariadicKind: u16
{
    A = 11
    B = 29
}

#test
{
    func variadicAnyOnly(values: ...)->u64 { return @countof(values) }
    const V0 = #run variadicAnyOnly()
    const V1 = #run variadicAnyOnly(1, 2, 3, 4)
    #assert(V0 == 0)
    #assert(V1 == 4)
}

#test
{
    func variadicAnyWithHead(a: s32, values: ...)->s32 { return a + cast(s32) @countof(values) }
    const V0 = #run variadicAnyWithHead(42)
    const V1 = #run variadicAnyWithHead(42, "x", 1, false)
    #assert(V0 == 42)
    #assert(V1 == 45)
}

#test
{
    func variadicAny(values: ...)->s32
    {
        let p0 = cast(*s32) @dataof(values[0])
        let p1 = cast(*s32) @dataof(values[1])
        let p2 = cast(*s32) @dataof(values[2])
        let p3 = cast(*s32) @dataof(values[3])
        return dref p0 + dref p1 + dref p2 + dref p3
    }

    const V0 = #run variadicAny(1's32, 2's32, 3's32, 4's32)
    #assert(V0 == 10)
}

#test
{
    func variadicAny(values: ...)->s64
    {
        let p0 = cast(*s64) @dataof(values[0])
        let p1 = cast(*s64) @dataof(values[1])
        let p2 = cast(*s64) @dataof(values[2])
        let p3 = cast(*s64) @dataof(values[3])
        return dref p0 + dref p1 + dref p2 + dref p3
    }

    const V0 = #run variadicAny(10's64, 20's64, 30's64, 40's64)
    #assert(#typeof(V0) == s64)
    #assert(V0 == 100's64)
}

#test
{
    func variadicAnyWithHead(a: s64, values: ...)->s64
    {
        let p0 = cast(*s64) @dataof(values[0])
        let p1 = cast(*s64) @dataof(values[1])
        return a + dref p0 + dref p1
    }

    const V0 = #run variadicAnyWithHead(100's64, 7's64, 8's64)
    #assert(#typeof(V0) == s64)
    #assert(V0 == 115's64)
}

#test
{
    func variadicAny(values: ...)->u32
    {
        let p0 = cast(*u32) @dataof(values[0])
        let p1 = cast(*u32) @dataof(values[1])
        let p2 = cast(*u32) @dataof(values[2])
        let p3 = cast(*u32) @dataof(values[3])
        return dref p0 + dref p1 + dref p2 + dref p3
    }

    const V0 = #run variadicAny(1'u32, 2'u32, 3'u32, 4'u32)
    #assert(#typeof(V0) == u32)
    #assert(V0 == 10'u32)
}

#test
{
    func variadicAnyWithHead(a: u32, values: ...)->u32
    {
        let p0 = cast(*u32) @dataof(values[0])
        let p1 = cast(*u32) @dataof(values[1])
        return a + dref p0 + dref p1
    }

    const V0 = #run variadicAnyWithHead(50'u32, 60'u32, 70'u32)
    #assert(#typeof(V0) == u32)
    #assert(V0 == 180'u32)
}

#test
{
    func variadicAny(values: ...)->f32
    {
        let p0 = cast(*f32) @dataof(values[0])
        let p1 = cast(*f32) @dataof(values[1])
        let p2 = cast(*f32) @dataof(values[2])
        return dref p0 + dref p1 + dref p2
    }

    const V0 = #run variadicAny(1.5'f32, 2.0'f32, 3.25'f32)
    #assert(#typeof(V0) == f32)
    #assert(V0 == 6.75'f32)
}

#test
{
    func variadicAnyWithHead(a: f32, values: ...)->f32
    {
        let p0 = cast(*f32) @dataof(values[0])
        let p1 = cast(*f32) @dataof(values[1])
        return a + dref p0 + dref p1
    }

    const V0 = #run variadicAnyWithHead(4.0'f32, 0.25'f32, 1.75'f32)
    #assert(#typeof(V0) == f32)
    #assert(V0 == 6.0'f32)
}

#test
{
    func variadicAny(values: ...)->f64
    {
        let p0 = cast(*f64) @dataof(values[0])
        let p1 = cast(*f64) @dataof(values[1])
        let p2 = cast(*f64) @dataof(values[2])
        let p3 = cast(*f64) @dataof(values[3])
        return dref p0 + dref p1 + dref p2 + dref p3
    }

    const V0 = #run variadicAny(1.0'f64, 2.0'f64, 3.0'f64, 4.0'f64)
    #assert(#typeof(V0) == f64)
    #assert(V0 == 10.0'f64)
}

#test
{
    func variadicAnyWithHead(a: f64, values: ...)->f64
    {
        let p0 = cast(*f64) @dataof(values[0])
        let p1 = cast(*f64) @dataof(values[1])
        return a + dref p0 + dref p1
    }

    const V0 = #run variadicAnyWithHead(10.0'f64, 0.5'f64, 1.25'f64)
    #assert(#typeof(V0) == f64)
    #assert(V0 == 11.75'f64)
}

#test
{
    func variadicAny(values: ...)->s32
    {
        let p0 = cast(*bool) @dataof(values[0])
        let p1 = cast(*bool) @dataof(values[1])
        let p2 = cast(*bool) @dataof(values[2])
        let p3 = cast(*bool) @dataof(values[3])
        return cast(s32) dref p0 + cast(s32) dref p1 + cast(s32) dref p2 + cast(s32) dref p3
    }

    const V0 = #run variadicAny(true, false, true, true)
    #assert(V0 == 3)
}

#test
{
    func variadicAnyWithHead(a: bool, values: ...)->s32
    {
        let p0 = cast(*bool) @dataof(values[0])
        let p1 = cast(*bool) @dataof(values[1])
        return cast(s32) a + cast(s32) dref p0 + cast(s32) dref p1
    }

    const V0 = #run variadicAnyWithHead(false, true, true)
    #assert(V0 == 2)
}

#test
{
    func variadicAny(values: ...)->s32
    {
        let p0 = cast(*rune) @dataof(values[0])
        let p1 = cast(*rune) @dataof(values[1])
        let p2 = cast(*rune) @dataof(values[2])
        return cast(s32) dref p0 + cast(s32) dref p1 + cast(s32) dref p2
    }

    const V0 = #run variadicAny('A', 'B', 'C')
    #assert(V0 == 198)
}

#test
{
    func variadicAnyWithHead(a: rune, values: ...)->s32
    {
        let p0 = cast(*rune) @dataof(values[0])
        let p1 = cast(*rune) @dataof(values[1])
        return cast(s32) a + cast(s32) dref p0 + cast(s32) dref p1
    }

    const V0 = #run variadicAnyWithHead('a', 'b', 'c')
    #assert(V0 == 294)
}

#test
{
    func variadicAnyWithHead(a: rune, values: ...)->u64 { return @countof(values) }
    const V0 = #run variadicAnyWithHead('a', 'b', 'c')
    #assert(V0 == 2)
}

#test
{
    func variadicAny(values: ...)->string { return cast(string) values[0] }

    const V0 = #run variadicAny("ab")
    #assert(V0 == "ab")
}

#test
{
    func variadicAny(values: ...)->u8
    {
        let s0 = cast(string) values[0]
        let s1 = cast(string) values[1]
        let s2 = cast(string) values[2]
        return s0[0] + s1[0] + s2[0]
    }

    const V0 = #run variadicAny("ab", "cd", "ef")
    #assert(#typeof(V0) == u8)
    #assert(V0 == 41'u8)
}

#test
{
    #[Swag.PrintMicro]
    func variadicAnyWithHead(a: string, values: ...)->u8
    {
        let s0 = cast(string) values[0]
        let s1 = cast(string) values[1]
        return a[0] + s0[0] + s1[0]
    }

    const V0 = #run variadicAnyWithHead("Az", "By", "Cx")
    #assert(#typeof(V0) == u8)
    #assert(V0 == 198'u8)
}

#test
{
    func variadicAny(values: ...)->bool
    {
        let p0 = cast(*s32) @dataof(values[0])
        let p1 = cast(*bool) @dataof(values[1])
        let p2 = cast(*f64) @dataof(values[2])
        return dref p0 == 1 and dref p1 and dref p2 == 12.5'f64 and cast(string) values[3] == "ab"
    }

    const V0 = #run variadicAny(1's32, true, 12.5'f64, "ab")
    #assert(V0)
}

#test
{
    func variadicAnyOnly(values: ...)->u64 { return @countof(values) }
    const V0 = #run variadicAnyOnly(1, 2.5, 3)
    #assert(V0 == 3)
}

// BUG:
//#test
//{
//    func variadicAny(values: ...)->bool
//    {
//        return @kindof(values[0]) == s32 and @kindof(values[1]) == f64 and @kindof(values[2]) == bool and @kindof(values[3]) == string
//    }
//
//    const V0 = #run variadicAny(7's32, 8.5'f64, true, "ok")
//    #assert(V0)
//}

// BUG:
//#test
//{
//    func variadicAny(values: ...)->bool
//    {
//        return @kindof(values[0]) == rune and @kindof(values[1]) == u64 and @kindof(values[2]) == f32
//    }
//
//    const V0 = #run variadicAny('A', 12'u64, 3.25'f32)
//    #assert(V0)
//}

// BUG:
//#test
//{
//    func variadicAny(values: ...)->s32
//    {
//        let p0 = cast(*VariadicPair) @dataof(values[0])
//        let p1 = cast(*VariadicPair) @dataof(values[1])
//        let v0 = dref p0
//        let v1 = dref p1
//        return v0.a + v0.b + v1.a + v1.b
//    }
//
//    const pair0: VariadicPair = {a: 2, b: 3}
//    const pair1: VariadicPair = {a: 5, b: 7}
//    const V0 = #run variadicAny(pair0, pair1)
//    #assert(V0 == 17)
//}

// BUG:
//#test
//{
//    func variadicAny(values: ...)->s32
//    {
//        let p0 = cast(*[4] s32) @dataof(values[0])
//        let p1 = cast(*[4] s32) @dataof(values[1])
//        let a0 = dref p0
//        let a1 = dref p1
//        return a0[0] + a0[3] + a1[1] + a1[2]
//    }
//
//    const arr0: [4] s32 = [1, 2, 3, 4]
//    const arr1: [4] s32 = [10, 20, 30, 40]
//    const V0 = #run variadicAny(arr0, arr1)
//    #assert(V0 == 55)
//}

// BUG:
//#test
//{
//    func variadicAny(values: ...)->u16
//    {
//        let p0 = cast(*VariadicKind) @dataof(values[0])
//        let p1 = cast(*VariadicKind) @dataof(values[1])
//        return cast(u16) dref p0 + cast(u16) dref p1
//    }
//
//    const V0 = #run variadicAny(VariadicKind.A, VariadicKind.B)
//    #assert(#typeof(V0) == u16)
//    #assert(V0 == 40'u16)
//}

// BUG:
//#test
//{
//    func variadicAny(values: ...)->u64
//    {
//        let p0 = cast(*VariadicPayload) @dataof(values[0])
//        let p1 = cast(*[2] u64) @dataof(values[1])
//        let s0 = cast(string) values[2]
//        let ptr = cast(*void) values[3]
//        let v0 = dref p0
//        let a1 = dref p1
//        return cast(u64) v0.arr[1] + cast(u64) v0.flag + cast(u64) v0.tag + a1[0] + a1[1] + cast(u64) s0[0] + cast(u64) (ptr != null)
//    }
//
//    const payload: VariadicPayload = {arr: [9, 8, 7], flag: true, tag: 5'u8}
//    const values: [2] u64 = [10'u64, 20'u64]
//    const ptr: *void = cast(*void) 0x11'u64
//    const V0 = #run variadicAny(payload, values, "Az", ptr)
//    #assert(#typeof(V0) == u64)
//    #assert(V0 == 110'u64)
//}

// BUG:
//#test
//{
//    func variadicAny(values: ...)->u16
//    {
//        let e0 = cast(VariadicKind) values[0]
//        let e1 = cast(VariadicKind) values[1]
//        return cast(u16) e0 + cast(u16) e1
//    }
//
//    const V0 = #run variadicAny(VariadicKind.A, VariadicKind.B)
//    #assert(#typeof(V0) == u16)
//    #assert(V0 == 40'u16)
//}

// BUG:
//#test
//{
//    func variadicAny(values: ...)->bool
//    {
//        let p0 = cast(*void) values[0]
//        let p1 = cast(*void) values[1]
//        return p0 == cast(*void) 0x1234'u64 and p1 == null
//    }
//
//    const V0 = #run variadicAny(cast(*void) 0x1234'u64, null)
//    #assert(V0)
//}

#test
{
    func variadicAny(values: ...)->any { return values["a"] } // swc-expected-error {{sema_err_index_not_int}}
    const V0 = #run variadicAny(1)
}
