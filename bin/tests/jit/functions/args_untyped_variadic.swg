#global fileprivate // swc-option suite-jit

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

#test
{
    func variadicAny(values: ...)->bool
    {
        let a = cast(s32) values[0]
        let b = cast(string) values[1]
        let c = cast(bool) values[2]
        return #typeof(a) == s32 and #typeof(b) == string and #typeof(c) == bool
    }

    const V0 = #run variadicAny(1, "ab", true)
    #assert(V0)
}

#test
{
    func variadicAny(values: ...)->s32
    {
        let p0 = cast(VariadicPair) values[0]
        let p1 = cast(VariadicPair) values[1]
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
        let a0 = cast([4] s32) values[0]
        let a1 = cast([4] s32) values[1]
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
        let e0 = cast(VariadicKind) values[0]
        let e1 = cast(VariadicKind) values[1]
        return cast(u16) e0 + cast(u16) e1
    }

    const V0 = #run variadicAny(VariadicKind.A, VariadicKind.B)
    #assert(#typeof(V0) == u16)
    #assert(V0 == 40'u16)
}

#test
{
    func variadicAny(values: ...)->bool
    {
        return @kindof(values[0]) == s32 and @kindof(values[1]) == f64 and @kindof(values[2]) == bool and @kindof(values[3]) == string
    }

    const V0 = #run variadicAny(7's32, 8.5'f64, true, "ok")
    #assert(V0)
}

#test
{
    func variadicAny(values: ...)->bool
    {
        return @kindof(values[0]) == rune and @kindof(values[1]) == u64 and @kindof(values[2]) == f32
    }

    const V0 = #run variadicAny(cast(rune) 'A', 12'u64, 3.25'f32)
    #assert(V0)
}

#test
{
    func variadicAny(values: ...)->s32
    {
        let p0 = cast(*VariadicPair) @dataof(values[0])
        let p1 = cast(*VariadicPair) @dataof(values[1])
        let v0 = dref p0
        let v1 = dref p1
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
        let p0 = cast(*[4] s32) @dataof(values[0])
        let p1 = cast(*[4] s32) @dataof(values[1])
        let a0 = dref p0
        let a1 = dref p1
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
        let p0 = cast(*VariadicKind) @dataof(values[0])
        let p1 = cast(*VariadicKind) @dataof(values[1])
        return cast(u16) dref p0 + cast(u16) dref p1
    }

    const V0 = #run variadicAny(VariadicKind.A, VariadicKind.B)
    #assert(#typeof(V0) == u16)
    #assert(V0 == 40'u16)
}

#test
{
    func variadicAny(values: ...)->u64
    {
        let p0 = cast(*VariadicPayload) @dataof(values[0])
        let p1 = cast(*[2] u64) @dataof(values[1])
        let s0 = cast(string) values[2]
        let ptr = cast(*void) values[3]
        let v0 = dref p0
        let a1 = dref p1
        return cast(u64) v0.arr[1] + cast(u64) v0.flag + cast(u64) v0.tag + a1[0] + a1[1] + cast(u64) s0[0] + cast(u64) (ptr != null)
    }

    const payload: VariadicPayload = {arr: [9, 8, 7], flag: true, tag: 5'u8}
    const values: [2] u64 = [10'u64, 20'u64]
    const ptr: *void = cast(*void) 0x11'u64
    const V0 = #run variadicAny(payload, values, "Az", ptr)
    #assert(#typeof(V0) == u64)
    #assert(V0 == 110'u64)
}

#test
{
    func variadicAny(values: ...)->u16
    {
        let e0 = cast(VariadicKind) values[0]
        let e1 = cast(VariadicKind) values[1]
        return cast(u16) e0 + cast(u16) e1
    }

    const V0 = #run variadicAny(VariadicKind.A, VariadicKind.B)
    #assert(#typeof(V0) == u16)
    #assert(V0 == 40'u16)
}

#test
{
    func variadicAny(values: ...)->bool
    {
        let p0 = cast(*void) values[0]
        let p1 = cast(*void) values[1]
        return p0 == cast(*void) 0x1234'u64 and p1 == null
    }

    const V0 = #run variadicAny(cast(*void) 0x1234'u64, null)
    #assert(V0)
}

#test
{
    func variadicAnyStressAKinds(values: ...)->bool
    {
        if @countof(values) != 4 do
            return false
        if @kindof(values[0]) != VariadicPair do
            return false
        if @kindof(values[1]) != VariadicPayload do
            return false
        if @kindof(values[2]) != VariadicKind do
            return false
        if @kindof(values[3]) != string do
            return false

        return true
    }

    func variadicAnyStressAPair(values: ...)->bool
    {
        let pair = cast(VariadicPair) values[0]
        return pair.a == 2 and pair.b == 3
    }

    func variadicAnyStressAPayload(values: ...)->bool
    {
        let payload = cast(VariadicPayload) values[1]
        return payload.arr[0] == 5 and
               payload.arr[1] == 8 and
               payload.arr[2] == 13 and
               payload.flag and
               payload.tag == 21'u8
    }

    func variadicAnyStressAKind(values: ...)->bool
    {
        let kind = cast(VariadicKind) values[2]
        return kind == VariadicKind.B
    }

    func variadicAnyStressAString(values: ...)->bool
    {
        let text = cast(string) values[3]
        return text == "untyped-variadic-stress"
    }

    const pair: VariadicPair = {a: 2, b: 3}
    const payload: VariadicPayload = {arr: [5, 8, 13], flag: true, tag: 21'u8}
    const V0 = #run variadicAnyStressAKinds(pair, payload, VariadicKind.B, "untyped-variadic-stress")
    const V1 = #run variadicAnyStressAPair(pair, payload, VariadicKind.B, "untyped-variadic-stress")
    const V2 = #run variadicAnyStressAPayload(pair, payload, VariadicKind.B, "untyped-variadic-stress")
    const V3 = #run variadicAnyStressAKind(pair, payload, VariadicKind.B, "untyped-variadic-stress")
    const V4 = #run variadicAnyStressAString(pair, payload, VariadicKind.B, "untyped-variadic-stress")
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
        if @countof(values) != 4 do
            return false
        if @kindof(values[0]) != *void do
            return false
        if @kindof(values[1]) != bool do
            return false
        if @kindof(values[2]) != rune do
            return false
        if @kindof(values[3]) != s64 do
            return false

        let ptr = cast(*void) values[0]
        let b = cast(bool) values[1]
        let r = cast(rune) values[2]
        let i64 = cast(s64) values[3]

        return ptr == cast(*void) 0x4040'u64 and
               b and
               r == 'K' and
               i64 == -123456789's64
    }

    const V0 = #run variadicAnyStressB(cast(*void) 0x4040'u64, true, cast(rune) 'K', -123456789's64)
    #assert(V0)
}

#test
{
    func variadicAnyStressC(values: ...)->bool
    {
        if @countof(values) != 3 do
            return false
        if @kindof(values[0]) != u64 do
            return false
        if @kindof(values[1]) != s32 do
            return false
        if @kindof(values[2]) != f64 do
            return false

        let u64v = cast(u64) values[0]
        let i32 = cast(s32) values[1]
        let f64v = cast(f64) values[2]

        return u64v == 987654321'u64 and
               i32 == -77 and
               f64v == 2.5'f64
    }

    const V0 = #run variadicAnyStressC(987654321'u64, -77's32, 2.5'f64)
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
        foreach it in values
        {
            var v = it
            return variadicAnySinkU64(cast(u64) v)
        }

        return 0'u64
    }

    const V0 = #run variadicAnyPassToTyped(1'u64)
    #assert(V0 == 1'u64)
}

#test
{
    func variadicAnyStressD(values: ...)->bool
    {
        if @countof(values) != 1 do
            return false
        if @kindof(values[0]) != [4] s32 do
            return false
        let arr = cast([4] s32) values[0]
        return arr[0] == -1 and arr[1] == 0 and arr[2] == 1 and arr[3] == 2
    }

    const V0 = #run variadicAnyStressD([-1, 0, 1, 2])
    #assert(V0)
}

#test
{
    func variadicAnyStressWithHead(a: VariadicPair, values: ...)->bool
    {
        @assert(a.a == 11 and a.b == 22)
        @assert(@countof(values) == 7)
        @assert(@kindof(values[0]) == VariadicPair)
        @assert(@kindof(values[1]) == VariadicPayload)
        @assert(@kindof(values[2]) == VariadicKind)
        @assert(@kindof(values[3]) == string)
        @assert(@kindof(values[4]) == bool)
        @assert(@kindof(values[5]) == f32)
        @assert(@kindof(values[6]) == *void)

        let p = cast(VariadicPair) values[0]
        let payload = cast(VariadicPayload) values[1]
        let kind = cast(VariadicKind) values[2]
        let text = cast(string) values[3]
        let b = cast(bool) values[4]
        let f = cast(f32) values[5]
        let ptr = cast(*void) values[6]

        @assert(p.a == 33 and p.b == 44)
        @assert(payload.arr[0] == 1 and payload.arr[1] == 2 and payload.arr[2] == 3)
        @assert(!payload.flag and payload.tag == 9'u8)
        @assert(kind == VariadicKind.A)
        @assert(text == "head-check")
        @assert(!b)
        @assert(f == 1.25'f32)
        @assert(ptr == cast(*void) 0x99'u64)
        return true
    }

    const head: VariadicPair = {a: 11, b: 22}
    const tail: VariadicPair = {a: 33, b: 44}
    const payload: VariadicPayload = {arr: [1, 2, 3], flag: false, tag: 9'u8}
    const V0 = #run variadicAnyStressWithHead(head, tail, payload, VariadicKind.A, "head-check", false, 1.25'f32, cast(*void) 0x99'u64)
    #assert(V0)
}

#test
{
    func variadicAny(values: ...)->any { return values["a"] } // swc-expected-error {{sema_err_index_not_int}}
    const V0 = #run variadicAny(1)
}

#test
{
    func variadicAnyStressWeighted(values: ...)->s32
    {
        var acc: s32 = 0

        foreach v, i in values
        {
            if @kindof(v) == s32
            {
                let p = cast(*s32) @dataof(v)
                acc += dref p * cast(s32) (i + 1)
                continue
            }

            if @kindof(v) == bool
            {
                let p = cast(*bool) @dataof(v)
                acc += cast(s32) dref p * 100
                continue
            }

            if @kindof(v) == rune
            {
                let p = cast(*rune) @dataof(v)
                acc += cast(s32) dref p
            }
        }

        return acc
    }

    const V0 = #run variadicAnyStressWeighted(1's32, 2's32, false, cast(rune) 'A', 4's32, true)
    #assert(V0 == 190)
}

#test
{
    func variadicAnyStressKinds(values: ...)->bool
    {
        if @countof(values) != 8 do
            return false

        return @kindof(values[0]) == s32 and
               @kindof(values[1]) == s64 and
               @kindof(values[2]) == u32 and
               @kindof(values[3]) == f64 and
               @kindof(values[4]) == bool and
               @kindof(values[5]) == rune and
               @kindof(values[6]) == string and
               @kindof(values[7]) == *void
    }

    const V0 = #run variadicAnyStressKinds(1's32, 2's64, 3'u32, 4.5'f64, true, cast(rune) 'X', "ok", cast(*void) 0x55'u64)
    #assert(V0)
}

#test
{
    func variadicAnyStressAggregates(values: ...)->u64
    {
        let p0 = cast(*VariadicPair) @dataof(values[0])
        let p1 = cast(*VariadicPayload) @dataof(values[1])
        let p2 = cast(*[3] s32) @dataof(values[2])

        let v0 = dref p0
        let v1 = dref p1
        let v2 = dref p2

        return cast(u64) (v0.a + v0.b + v1.arr[0] + v1.arr[1] + v1.arr[2] + v1.tag + v2[0] + v2[1] + v2[2])
    }

    const pair: VariadicPair = {a: 2, b: 3}
    const payload: VariadicPayload = {arr: [4, 5, 6], flag: true, tag: 7'u8}
    const arr: [3] s32 = [8, 9, 10]
    const V0 = #run variadicAnyStressAggregates(pair, payload, arr)
    #assert(V0 == 54'u64)
}
