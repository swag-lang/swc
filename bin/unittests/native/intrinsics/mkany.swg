#global private

struct MkanyPair
{
    a: s32
    b: s32
}

enum MkanyKind: u16
{
    A = 3
    B = 9
}

#[Swag.Strict]
alias MkanyStrictS32Ptr   = *s32

#[Swag.Strict]
alias MkanyStrictVoidPtr  = *void

#[Swag.Strict]
alias MkanyStrictS32      = s32

#[Swag.Strict]
alias MkanyStrictTypeInfo = typeinfo

#test
{
    var x: s32 = 42
    let a: any = Swag.makeAny(&x, s32)
    let p      = cast(*s32) a.buffer

    Swag.assert(Swag.kindOf(a) == s32)
    Swag.assert(p[] == 42)
}

#test
{
    var x: s32 = 123
    var y: s32 = 7
    var a: any = Swag.makeAny(&x, s32)
    var b: any = Swag.makeAny(&y, s32)
    b = a
    let p = cast(*s32) b.buffer

    Swag.assert(p[] == 123)
}

#test
{
    var p: MkanyPair = {a: 11, b: 31}
    let a: any       = Swag.makeAny(&p, MkanyPair)
    p.b = 10
    let data  = cast(*MkanyPair) a.buffer
    let value = data[]

    Swag.assert(Swag.kindOf(a) == MkanyPair)
    Swag.assert(value.a == 11)
    Swag.assert(value.b == 10)
}

#test
{
    var arr: [6] s32 = [1, 2, 3, 4, 5, 6]
    let ptr          = cast(*[6] s32) &arr
    let a:   any     = Swag.makeAny(ptr, [6] s32)
    let p            = cast(*[6] s32) a.buffer
    let value        = p[]
    var acc: s32     = 0
    for v, i in value
    {
        acc += v * cast(s32) (i + 1)
    }

    Swag.assert(acc == 91)
}

#test
{
    var x: s32 = 55
    let ptr    = cast([*] void) &x
    let a: any = Swag.makeAny(ptr, s32)
    let p      = cast(*s32) a.buffer

    Swag.assert(Swag.kindOf(a) == s32)
    Swag.assert(p[] == 55)
}

#test
{
    var k: MkanyKind = MkanyKind.B
    let a: any       = Swag.makeAny(&k, MkanyKind)
    let p            = cast(*MkanyKind) a.buffer

    Swag.assert(Swag.kindOf(a) == MkanyKind)
    Swag.assert(p[] == MkanyKind.B)
}

#test
{
    var s0: s64 = 10
    var s1: s64 = 20
    var s2: s64 = 30
    var s3: s64 = 40
    var a:  any = Swag.makeAny(&s0, s64)
    var b:  any = Swag.makeAny(&s1, s64)
    var c:  any = Swag.makeAny(&s2, s64)
    var d:  any = Swag.makeAny(&s3, s64)

    b = a
    c = b
    d = c
    a = Swag.makeAny(&s3, s64)
    b = Swag.makeAny(&s2, s64)
    c = Swag.makeAny(&s1, s64)
    d = Swag.makeAny(&s0, s64)

    let p0 = cast(*s64) a.buffer
    let p1 = cast(*s64) b.buffer
    let p2 = cast(*s64) c.buffer
    let p3 = cast(*s64) d.buffer

    Swag.assert(cast(u64) (p0[] + p1[] + p2[] + p3[]) == 100'u64)
}

#test
{
    var b:  bool = true
    var r:  rune = 'A'
    let ab: any  = Swag.makeAny(&b, bool)
    let ar: any  = Swag.makeAny(&r, rune)
    let pb       = cast(*bool) ab.buffer
    let pr       = cast(*rune) ar.buffer

    Swag.assert(cast(s32) pb[] + cast(s32) pr[] == 66)
}

#test
{
    var boxed: any
    var value: s64 = 9000
    boxed = Swag.makeAny(&value, s64)
    let p = cast(*s64) boxed.buffer

    Swag.assert(Swag.kindOf(boxed) == s64)
    Swag.assert(p[] == 9000)
}

#test
{
    var text:  string = "alpha"
    let boxed: any    = Swag.makeAny(&text, string)
    let ptr           = cast(*string) boxed.buffer

    text = "beta"

    Swag.assert(Swag.kindOf(boxed) == string)
    Swag.assert(ptr[] == "beta")
    Swag.assert((ptr[]).count == 4)
    Swag.assert(cast(string) boxed == "beta")
}

func mkanyCastStringFromAny(value: any)->string
{
    let reboxed: any = Swag.makeAny(value.buffer, Swag.kindOf(value))
    return cast(string) reboxed
}

func mkanyStringBytesLen(bytes: const [..] u8?)->u64
{
    return bytes.count
}

func mkanyCastStringToBytesFromAny(value: any)->u64
{
    let reboxed: any = Swag.makeAny(value.buffer, Swag.kindOf(value))
    return mkanyStringBytesLen(cast(string) reboxed)
}

#test
{
    Swag.assert(mkanyCastStringFromAny("gamma") == "gamma")
    Swag.assert(mkanyCastStringToBytesFromAny("delta") == 5)
}

#test
{
    var buffer: [4] s32  = [3, 6, 9, 12]
    var values: [..] s32 = buffer
    let boxed:  any      = Swag.makeAny(&values, [..] s32)
    let ptr              = cast(*[..] s32) boxed.buffer

    values[1] = 77
    values    = buffer[1 to 3]

    Swag.assert(Swag.kindOf(boxed) == [..] s32)
    Swag.assert((ptr[]).count == 3)
    Swag.assert(ptr[][0] == 77)
    Swag.assert(ptr[][2] == 12)
}

#test
{
    var x:     s32 = 314
    let ptr        = cast(MkanyStrictS32Ptr) &x
    let boxed: any = Swag.makeAny(ptr, s32)
    let data       = cast(*s32) boxed.buffer

    Swag.assert(Swag.kindOf(boxed) == s32)
    Swag.assert(data[] == 314)
}

#test
{
    var x:     s32 = 271
    let ptr        = cast(MkanyStrictVoidPtr) &x
    let boxed: any = Swag.makeAny(ptr, s32)
    let data       = cast(*s32) boxed.buffer

    Swag.assert(Swag.kindOf(boxed) == s32)
    Swag.assert(data[] == 271)
}

#test
{
    var x:     s32 = 812
    let info       = cast(MkanyStrictTypeInfo) #typeof(s32)
    let boxed: any = Swag.makeAny(&x, info)
    let data       = cast(*s32) boxed.buffer

    Swag.assert(Swag.kindOf(boxed) == s32)
    Swag.assert(data[] == 812)
}

#test
{
    var x          = cast(MkanyStrictS32) 409
    let boxed: any = Swag.makeAny(&x, MkanyStrictS32)

    Swag.assert(Swag.kindOf(boxed) == MkanyStrictS32)
    Swag.assert(cast(MkanyStrictS32) boxed == cast(MkanyStrictS32) 409)
}

#test
{
    var text       = "omega"
    let info       = #typeof(text)
    let boxed: any = Swag.makeAny(&text, info)

    Swag.assert(Swag.kindOf(boxed) == string)
    Swag.assert(cast(string) boxed == "omega")
}

#test
{
    var value           = 733's32
    let ptr: const *s32 = &value
    let boxed           = Swag.makeAny(ptr, s32)
    let data            = cast(const *s32) boxed
    let raw             = cast(const *s32) boxed.buffer

    Swag.assert(Swag.kindOf(boxed) == s32)
    Swag.assert(data[] == 733)
    Swag.assert(raw[] == 733)
}

#test
{
    var value             = 123's32
    let ptr:   const *s32 = &value
    let boxed: const any  = Swag.makeAny(ptr, s32)
    let data              = cast(const *s32) boxed

    #assert(#typeof(boxed) == const any)
    Swag.assert(data[] == 123)
}

#test
{
    var storage: [3] u8        = [3'u8, 5'u8, 8'u8]
    let bytes:   const [..] u8 = cast(const [..] u8) storage
    let boxed                  = Swag.makeAny(&bytes, const [..] u8)
    let view                   = cast(const [..] u8) boxed

    Swag.assert(view.count == 3)
    Swag.assert(view[0] == 3'u8)
    Swag.assert(view[2] == 8'u8)
}

#test
{
    var storage: [4] u8        = ['a'u8, 'n'u8, 'y'u8, 0]
    let text:    const cstring = cast(const cstring) &storage[0]
    let boxed                  = Swag.makeAny(&text, const cstring)
    let view                   = cast(const cstring) boxed

    Swag.assert(view.count == 3)
    Swag.assert(view[0] == 'a'u8)
    Swag.assert(view[2] == 'y'u8)
}

#test
{
    var storage: [6] u8        = ['b'u8, 'o'u8, 'x'u8, 'e'u8, 'd'u8, 0]
    let text:    const cstring = cast(const cstring) &storage[0]
    let boxed:   const any     = text
    let view                   = cast(const cstring) boxed

    Swag.assert(view.count == 5)
    Swag.assert(view[0] == 'b'u8)
    Swag.assert(view[4] == 'd'u8)
}
