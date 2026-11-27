#global private

enum PlainArrayIndexKind
{
    First
    Second
}

func indexPlainArrayWithEnum()->s32
{
    const values = [1, 2]
    return values[PlainArrayIndexKind.First]     // swc-expected-error {{sema_err_index_not_int}}
}

struct VariadicPair
{
    a: s32
    b: s32
}

struct VariadicPayload
{
    arr:  [3] s32
    flag: bool
    tag:  u8
}

enum VariadicKind: u16
{
    A = 11
    B = 29
}

#test
{
    func variadicAnyOnly(values: ...)->u64 { return values.count }
    const V0 = #run variadicAnyOnly()
    const V1 = #run variadicAnyOnly(1, 2, 3, 4)
    #assert(V0 == 0)
    #assert(V1 == 4)
}

#test
{
    func variadicAnyWithHead(a: s32, values: ...)->s32 { return a + cast(s32, values.count) }
    const V0 = #run variadicAnyWithHead(42)
    const V1 = #run variadicAnyWithHead(42, "x", 1, false)
    #assert(V0 == 42)
    #assert(V1 == 45)
}

#test
{
    func variadicAny(values: ...)->s32
    {
        let p0 = cast(*s32, values[0].buffer)
        let p1 = cast(*s32, values[1].buffer)
        let p2 = cast(*s32, values[2].buffer)
        let p3 = cast(*s32, values[3].buffer)
        return p0[] + p1[] + p2[] + p3[]
    }

    const V0 = #run variadicAny(1_s32, 2_s32, 3_s32, 4_s32)
    #assert(V0 == 10)
}

#test
{
    func variadicAny(values: ...)->s64
    {
        let p0 = cast(*s64, values[0].buffer)
        let p1 = cast(*s64, values[1].buffer)
        let p2 = cast(*s64, values[2].buffer)
        let p3 = cast(*s64, values[3].buffer)
        return p0[] + p1[] + p2[] + p3[]
    }

    const V0 = #run variadicAny(10_s64, 20_s64, 30_s64, 40_s64)
    #assert(#typeof(V0) == s64)
    #assert(V0 == 100_s64)
}

#test
{
    func variadicAnyWithHead(a: s64, values: ...)->s64
    {
        let p0 = cast(*s64, values[0].buffer)
        let p1 = cast(*s64, values[1].buffer)
        return a + p0[] + p1[]
    }

    const V0 = #run variadicAnyWithHead(100_s64, 7_s64, 8_s64)
    #assert(#typeof(V0) == s64)
    #assert(V0 == 115_s64)
}

#test
{
    func variadicAny(values: ...)->u32
    {
        let p0 = cast(*u32, values[0].buffer)
        let p1 = cast(*u32, values[1].buffer)
        let p2 = cast(*u32, values[2].buffer)
        let p3 = cast(*u32, values[3].buffer)
        return p0[] + p1[] + p2[] + p3[]
    }

    const V0 = #run variadicAny(1_u32, 2_u32, 3_u32, 4_u32)
    #assert(#typeof(V0) == u32)
    #assert(V0 == 10_u32)
}

#test
{
    func variadicAnyWithHead(a: u32, values: ...)->u32
    {
        let p0 = cast(*u32, values[0].buffer)
        let p1 = cast(*u32, values[1].buffer)
        return a + p0[] + p1[]
    }

    const V0 = #run variadicAnyWithHead(50_u32, 60_u32, 70_u32)
    #assert(#typeof(V0) == u32)
    #assert(V0 == 180_u32)
}

#test
{
    func variadicAny(values: ...)->f32
    {
        let p0 = cast(*f32, values[0].buffer)
        let p1 = cast(*f32, values[1].buffer)
        let p2 = cast(*f32, values[2].buffer)
        return p0[] + p1[] + p2[]
    }

    const V0 = #run variadicAny(1.5_f32, 2.0_f32, 3.25_f32)
    #assert(#typeof(V0) == f32)
    #assert(V0 == 6.75_f32)
}

#test
{
    func variadicAnyWithHead(a: f32, values: ...)->f32
    {
        let p0 = cast(*f32, values[0].buffer)
        let p1 = cast(*f32, values[1].buffer)
        return a + p0[] + p1[]
    }

    const V0 = #run variadicAnyWithHead(4.0_f32, 0.25_f32, 1.75_f32)
    #assert(#typeof(V0) == f32)
    #assert(V0 == 6.0_f32)
}

#test
{
    func variadicAny(values: ...)->f64
    {
        let p0 = cast(*f64, values[0].buffer)
        let p1 = cast(*f64, values[1].buffer)
        let p2 = cast(*f64, values[2].buffer)
        let p3 = cast(*f64, values[3].buffer)
        return p0[] + p1[] + p2[] + p3[]
    }

    const V0 = #run variadicAny(1.0_f64, 2.0_f64, 3.0_f64, 4.0_f64)
    #assert(#typeof(V0) == f64)
    #assert(V0 == 10.0_f64)
}

#test
{
    func variadicAnyWithHead(a: f64, values: ...)->f64
    {
        let p0 = cast(*f64, values[0].buffer)
        let p1 = cast(*f64, values[1].buffer)
        return a + p0[] + p1[]
    }

    const V0 = #run variadicAnyWithHead(10.0_f64, 0.5_f64, 1.25_f64)
    #assert(#typeof(V0) == f64)
    #assert(V0 == 11.75_f64)
}

#test
{
    func variadicAny(values: ...)->s32
    {
        let p0 = cast(*bool, values[0].buffer)
        let p1 = cast(*bool, values[1].buffer)
        let p2 = cast(*bool, values[2].buffer)
        let p3 = cast(*bool, values[3].buffer)
        return cast(s32, p0[]) + cast(s32, p1[]) + cast(s32, p2[]) + cast(s32, p3[])
    }

    const V0 = #run variadicAny(true, false, true, true)
    #assert(V0 == 3)
}

#test
{
    func variadicAnyWithHead(a: bool, values: ...)->s32
    {
        let p0 = cast(*bool, values[0].buffer)
        let p1 = cast(*bool, values[1].buffer)
        return cast(s32, a) + cast(s32, p0[]) + cast(s32, p1[])
    }

    const V0 = #run variadicAnyWithHead(false, true, true)
    #assert(V0 == 2)
}

#test
{
    func variadicAny(values: ...)->s32
    {
        let p0 = cast(*rune, values[0].buffer)
        let p1 = cast(*rune, values[1].buffer)
        let p2 = cast(*rune, values[2].buffer)
        return cast(s32, p0[]) + cast(s32, p1[]) + cast(s32, p2[])
    }

    const V0 = #run variadicAny('A', 'B', 'C')
    #assert(V0 == 198)
}

#test
{
    func variadicAnyWithHead(a: rune, values: ...)->s32
    {
        let p0 = cast(*rune, values[0].buffer)
        let p1 = cast(*rune, values[1].buffer)
        return cast(s32, a) + cast(s32, p0[]) + cast(s32, p1[])
    }

    const V0 = #run variadicAnyWithHead('a', 'b', 'c')
    #assert(V0 == 294)
}

#test
{
    func variadicAnyWithHead(a: rune, values: ...)->u64 { discard a; return values.count }
    const V0 = #run variadicAnyWithHead('a', 'b', 'c')
    #assert(V0 == 2)
}

#test
{
    func variadicAny(values: ...)->string { return assume cast(string, values[0]) }

    const V0 = #run variadicAny("ab")
    #assert(V0 == "ab")
}

#test
{
    func variadicAny(values: ...)->u8
    {
        let s0 = assume cast(string, values[0])
        let s1 = assume cast(string, values[1])
        let s2 = assume cast(string, values[2])
        return cast #wrap(u8, (cast(u16, s0[0]) + cast(u16, s1[0]) + cast(u16, s2[0])))
    }

    const V0 = #run variadicAny("ab", "cd", "ef")
    #assert(#typeof(V0) == u8)
    #assert(V0 == 41_u8)
}

#test
{
    func variadicAnyWithHead(a: string, values: ...)->u8
    {
        let s0 = assume cast(string, values[0])
        let s1 = assume cast(string, values[1])
        return a[0] + s0[0] + s1[0]
    }

    const V0 = #run variadicAnyWithHead("Az", "By", "Cx")
    #assert(#typeof(V0) == u8)
    #assert(V0 == 198_u8)
}

#test
{
    func variadicAny(values: ...)->bool
    {
        let p0 = cast(*s32, values[0].buffer)
        let p1 = cast(*bool, values[1].buffer)
        let p2 = cast(*f64, values[2].buffer)
        return p0[] == 1 and p1[] and p2[] == 12.5_f64 and assume cast(string, values[3]) == "ab"
    }

    const V0 = #run variadicAny(1_s32, true, 12.5_f64, "ab")
    #assert(V0)
}

#test
{
    func variadicAnyOnly(values: ...)->u64 { return values.count }
    const V0 = #run variadicAnyOnly(1, 2.5, 3)
    #assert(V0 == 3)
}

#test
{
    func variadicAny(values: ...)->bool
    {
        let a = assume cast(s32, values[0])
        let b = assume cast(string, values[1])
        let c = assume cast(bool, values[2])
        return #typeof(a) == s32 and #typeof(b) == string and #typeof(c) == bool
    }

    const V0 = #run variadicAny(1, "ab", true)
    #assert(V0)
}

#test
{
    func variadicAny(values: ...)->s32
    {
        let p0 = assume cast(VariadicPair, values[0])
        let p1 = assume cast(VariadicPair, values[1])
        return p0.a + p0.b + p1.a + p1.b
    }

    const pair0: VariadicPair = {a: 2, b: 3}
    const pair1: VariadicPair = {a: 5, b: 7}
    const V0 = #run variadicAny(pair0, pair1)
    #assert(V0 == 17)
}

#test
{
    func variadicAny(values: ...)->s32
    {
        let a0 = assume cast([4] s32, values[0])
        let a1 = assume cast([4] s32, values[1])
        return a0[0] + a0[3] + a1[1] + a1[2]
    }

    const arr0: [4] s32 = [1, 2, 3, 4]
    const arr1: [4] s32 = [10, 20, 30, 40]
    const V0 = #run variadicAny(arr0, arr1)
    #assert(V0 == 55)
}

#test
{
    func variadicAny(values: ...)->u16
    {
        let e0 = assume cast(VariadicKind, values[0])
        let e1 = assume cast(VariadicKind, values[1])
        return cast(u16, e0) + cast(u16, e1)
    }

    const V0 = #run variadicAny(VariadicKind.A, VariadicKind.B)
    #assert(#typeof(V0) == u16)
    #assert(V0 == 40_u16)
}

#test
{
    func variadicAny(values: ...)->bool
    {
        return Swag.kindOf(values[0]) == s32 and
               Swag.kindOf(values[1]) == f64 and
               Swag.kindOf(values[2]) == bool and
               Swag.kindOf(values[3]) == string
    }

    const V0 = #run variadicAny(7_s32, 8.5_f64, true, "ok")
    #assert(V0)
}

#test
{
    func variadicAny(values: ...)->bool
    {
        return Swag.kindOf(values[0]) == rune and
               Swag.kindOf(values[1]) == u64 and
               Swag.kindOf(values[2]) == f32
    }

    const V0 = #run variadicAny(cast(rune, 'A'), 12_u64, 3.25_f32)
    #assert(V0)
}

#test
{
    func variadicAny(values: ...)->s32
    {
        let p0 = cast(*VariadicPair, values[0].buffer)
        let p1 = cast(*VariadicPair, values[1].buffer)
        let v0 = p0[]
        let v1 = p1[]
        return v0.a + v0.b + v1.a + v1.b
    }

    const pair0: VariadicPair = {a: 2, b: 3}
    const pair1: VariadicPair = {a: 5, b: 7}
    const V0 = #run variadicAny(pair0, pair1)
    #assert(V0 == 17)
}

#test
{
    func variadicAny(values: ...)->s32
    {
        let p0 = cast(*[4] s32, values[0].buffer)
        let p1 = cast(*[4] s32, values[1].buffer)
        let a0 = p0[]
        let a1 = p1[]
        return a0[0] + a0[3] + a1[1] + a1[2]
    }

    const arr0: [4] s32 = [1, 2, 3, 4]
    const arr1: [4] s32 = [10, 20, 30, 40]
    const V0 = #run variadicAny(arr0, arr1)
    #assert(V0 == 55)
}

#test
{
    func variadicAny(values: ...)->u16
    {
        let p0 = cast(*VariadicKind, values[0].buffer)
        let p1 = cast(*VariadicKind, values[1].buffer)
        return cast(u16, p0[]) + cast(u16, p1[])
    }

    const V0 = #run variadicAny(VariadicKind.A, VariadicKind.B)
    #assert(#typeof(V0) == u16)
    #assert(V0 == 40_u16)
}

#test
{
    func variadicAny(values: ...)->u64
    {
        let p0  = cast(*VariadicPayload, values[0].buffer)
        let p1  = cast(*[2] u64, values[1].buffer)
        let s0  = assume cast(string, values[2])
        let ptr = assume cast(*void, values[3])
        let v0  = p0[]
        let a1  = p1[]
        return cast(u64, v0.arr[1]) + cast(u64, v0.flag) + cast(u64, v0.tag) + a1[0] + a1[1] + cast(u64, s0[0]) + cast(u64, (ptr != null))
    }

    const payload: VariadicPayload = {arr: [9, 8, 7], flag: true, tag: 5_u8}
    const values:  [2] u64         = [10_u64, 20_u64]
    const ptr:     *void           = cast(*void, 0x11_u64)
    const V0 = #run variadicAny(payload, values, "Az", ptr)
    #assert(#typeof(V0) == u64)
    #assert(V0 == 110_u64)
}

#test
{
    func variadicAny(values: ...)->u16
    {
        let e0 = assume cast(VariadicKind, values[0])
        let e1 = assume cast(VariadicKind, values[1])
        return cast(u16, e0) + cast(u16, e1)
    }

    const V0 = #run variadicAny(VariadicKind.A, VariadicKind.B)
    #assert(#typeof(V0) == u16)
    #assert(V0 == 40_u16)
}

#test
{
    func variadicAny(values: ...)->bool
    {
        let p0 = assume cast(*void, values[0])
        let p1 = assume cast(*void?, values[1])
        return p0 == cast(*void, 0x1234_u64) and p1 == null
    }

    const V0 = #run variadicAny(cast(*void, 0x1234_u64), null)
    #assert(V0)
}

#test
{
    func variadicAnyStressAKinds(values: ...)->bool
    {
        if values.count != 4
        {
            return false
        }
        if Swag.kindOf(values[0]) != VariadicPair
        {
            return false
        }
        if Swag.kindOf(values[1]) != VariadicPayload
        {
            return false
        }
        if Swag.kindOf(values[2]) != VariadicKind
        {
            return false
        }
        if Swag.kindOf(values[3]) != string
        {
            return false
        }

        return true
    }

    func variadicAnyStressAPair(values: ...)->bool
    {
        let pair = assume cast(VariadicPair, values[0])
        return pair.a == 2 and pair.b == 3
    }

    func variadicAnyStressAPayload(values: ...)->bool
    {
        let payload = assume cast(VariadicPayload, values[1])
        return payload.arr[0] == 5 and
               payload.arr[1] == 8 and
               payload.arr[2] == 13 and
               payload.flag and
               payload.tag == 21_u8
    }

    func variadicAnyStressAKind(values: ...)->bool
    {
        let kind = assume cast(VariadicKind, values[2])
        return kind == VariadicKind.B
    }

    func variadicAnyStressAString(values: ...)->bool
    {
        let text = assume cast(string, values[3])
        return text == "untyped-variadic-stress"
    }

    const pair:    VariadicPair    = {a: 2, b: 3}
    const payload: VariadicPayload = {arr: [5, 8, 13], flag: true, tag: 21_u8}
    const V0                       = #run variadicAnyStressAKinds(pair, payload, VariadicKind.B, "untyped-variadic-stress")
    const V1                       = #run variadicAnyStressAPair(pair, payload, VariadicKind.B, "untyped-variadic-stress")
    const V2                       = #run variadicAnyStressAPayload(pair, payload, VariadicKind.B, "untyped-variadic-stress")
    const V3                       = #run variadicAnyStressAKind(pair, payload, VariadicKind.B, "untyped-variadic-stress")
    const V4                       = #run variadicAnyStressAString(pair, payload, VariadicKind.B, "untyped-variadic-stress")
    #assert(V0)
    #assert(V1)
    #assert(V2)
    #assert(V3)
    #assert(V4)
}

#test
{
    func variadicAnyStressB(values: ...)->bool
    {
        if values.count != 4
        {
            return false
        }
        if Swag.kindOf(values[0]) != *void
        {
            return false
        }
        if Swag.kindOf(values[1]) != bool
        {
            return false
        }
        if Swag.kindOf(values[2]) != rune
        {
            return false
        }
        if Swag.kindOf(values[3]) != s64
        {
            return false
        }

        let ptr = assume cast(*void, values[0])
        let b   = assume cast(bool, values[1])
        let r   = assume cast(rune, values[2])
        let i64 = assume cast(s64, values[3])

        return ptr == cast(*void, 0x4040_u64) and
               b and
               r == 'K' and
               i64 == -123456789_s64
    }

    const V0 = #run variadicAnyStressB(cast(*void, 0x4040_u64), true, cast(rune, 'K'), -123456789_s64)
    #assert(V0)
}

#test
{
    func variadicAnyStressC(values: ...)->bool
    {
        if values.count != 3
        {
            return false
        }
        if Swag.kindOf(values[0]) != u64
        {
            return false
        }
        if Swag.kindOf(values[1]) != s32
        {
            return false
        }
        if Swag.kindOf(values[2]) != f64
        {
            return false
        }

        let u64v = assume cast(u64, values[0])
        let i32  = assume cast(s32, values[1])
        let f64v = assume cast(f64, values[2])

        return u64v == 987654321_u64 and
               i32 == -77 and
               f64v == 2.5_f64
    }

    const V0 = #run variadicAnyStressC(987654321_u64, -77_s32, 2.5_f64)
    #assert(V0)
}

#test
{
    func variadicAnySinkU64(v: u64)->u64
    {
        return v
    }

    func variadicAnyPassToTyped(values: ...)->u64
    {
        for it in values
        {
            var v = it
            return variadicAnySinkU64(assume cast(u64, v))
        }

        return 0_u64
    }

    const V0 = #run variadicAnyPassToTyped(1_u64)
    #assert(V0 == 1_u64)
}

#test
{
    func variadicAnyStressD(values: ...)->bool
    {
        if values.count != 1
        {
            return false
        }
        if Swag.kindOf(values[0]) != [4] s32
        {
            return false
        }
        let arr = assume cast([4] s32, values[0])
        return arr[0] == -1 and arr[1] == 0 and arr[2] == 1 and arr[3] == 2
    }

    const V0 = #run variadicAnyStressD([-1, 0, 1, 2])
    #assert(V0)
}

#test
{
    func variadicAnyStressWithHead(a: VariadicPair, values: ...)->bool
    {
        Swag.assert(a.a == 11 and a.b == 22)
        Swag.assert(values.count == 7)
        Swag.assert(Swag.kindOf(values[0]) == VariadicPair)
        Swag.assert(Swag.kindOf(values[1]) == VariadicPayload)
        Swag.assert(Swag.kindOf(values[2]) == VariadicKind)
        Swag.assert(Swag.kindOf(values[3]) == string)
        Swag.assert(Swag.kindOf(values[4]) == bool)
        Swag.assert(Swag.kindOf(values[5]) == f32)
        Swag.assert(Swag.kindOf(values[6]) == *void)

        let p       = assume cast(VariadicPair, values[0])
        let payload = assume cast(VariadicPayload, values[1])
        let kind    = assume cast(VariadicKind, values[2])
        let text    = assume cast(string, values[3])
        let b       = assume cast(bool, values[4])
        let f       = assume cast(f32, values[5])
        let ptr     = assume cast(*void, values[6])

        Swag.assert(p.a == 33 and p.b == 44)
        Swag.assert(payload.arr[0] == 1 and payload.arr[1] == 2 and payload.arr[2] == 3)
        Swag.assert(not payload.flag and payload.tag == 9_u8)
        Swag.assert(kind == VariadicKind.A)
        Swag.assert(text == "head-check")
        Swag.assert(not b)
        Swag.assert(f == 1.25_f32)
        Swag.assert(ptr == cast(*void, 0x99_u64))
        return true
    }

    const head:    VariadicPair    = {a: 11, b: 22}
    const tail:    VariadicPair    = {a: 33, b: 44}
    const payload: VariadicPayload = {arr: [1, 2, 3], flag: false, tag: 9_u8}
    const V0 = #run variadicAnyStressWithHead(head, tail, payload, VariadicKind.A, "head-check", false, 1.25_f32, cast(*void, 0x99_u64))
    #assert(V0)
}

#test
{
    func variadicAny(values: ...)->any { return values["a"] }     // swc-expected-error {{sema_err_index_not_int}}
    const V0 = #run variadicAny(1)
}

#test
{
    func variadicAnyStressWeighted(values: ...)->s32
    {
        var acc: s32 = 0

        for v, i in values
        {
            if Swag.kindOf(v) == s32
            {
                let p = cast(*s32, v.buffer)
                acc += p[] * cast(s32, (i + 1))
                continue
            }

            if Swag.kindOf(v) == bool
            {
                let p = cast(*bool, v.buffer)
                acc += cast(s32, p[]) * 100
                continue
            }

            if Swag.kindOf(v) == rune
            {
                let p = cast(*rune, v.buffer)
                acc += cast(s32, p[])
            }
        }

        return acc
    }

    const V0 = #run variadicAnyStressWeighted(1_s32, 2_s32, false, cast(rune, 'A'), 4_s32, true)
    #assert(V0 == 190)
}

#test
{
    func variadicAnyStressKinds(values: ...)->bool
    {
        if values.count != 8
        {
            return false
        }

        return Swag.kindOf(values[0]) == s32 and
               Swag.kindOf(values[1]) == s64 and
               Swag.kindOf(values[2]) == u32 and
               Swag.kindOf(values[3]) == f64 and
               Swag.kindOf(values[4]) == bool and
               Swag.kindOf(values[5]) == rune and
               Swag.kindOf(values[6]) == string and
               Swag.kindOf(values[7]) == *void
    }

    const V0 = #run variadicAnyStressKinds(1_s32, 2_s64, 3_u32, 4.5_f64, true, cast(rune, 'X'), "ok", cast(*void, 0x55_u64))
    #assert(V0)
}

#test
{
    func variadicAnyStressAggregates(values: ...)->u64
    {
        let p0 = cast(*VariadicPair, values[0].buffer)
        let p1 = cast(*VariadicPayload, values[1].buffer)
        let p2 = cast(*[3] s32, values[2].buffer)

        let v0 = p0[]
        let v1 = p1[]
        let v2 = p2[]

        return cast(u64, (v0.a + v0.b + v1.arr[0] + v1.arr[1] + v1.arr[2] + v1.tag + v2[0] + v2[1] + v2[2]))
    }

    const pair:    VariadicPair    = {a: 2, b: 3}
    const payload: VariadicPayload = {arr: [4, 5, 6], flag: true, tag: 7_u8}
    const arr:     [3] s32         = [8, 9, 10]
    const V0 = #run variadicAnyStressAggregates(pair, payload, arr)
    #assert(V0 == 54_u64)
}
