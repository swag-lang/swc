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
alias MkanyStrictS32Ptr = *s32

#[Swag.Strict]
alias MkanyStrictVoidPtr = *void

#[Swag.Strict]
alias MkanyStrictS32 = s32

#[Swag.Strict]
alias MkanyStrictTypeInfo = typeinfo

#test
{
    var x: s32 = 42
    let a: any = @mkany(&x, s32)
    let p = cast(*s32) @dataof(a)

    @assert(@kindof(a) == s32)
    @assert(dref p == 42)
}

#test
{
    var x: s32 = 123
    var y: s32 = 7
    var a: any = @mkany(&x, s32)
    var b: any = @mkany(&y, s32)
    b = a
    let p = cast(*s32) @dataof(b)

    @assert(dref p == 123)
}

#test
{
    var p: MkanyPair = {a: 11, b: 31}
    let a: any = @mkany(&p, MkanyPair)
    p.b = 10
    let data = cast(*MkanyPair) @dataof(a)
    let value = dref data

    @assert(@kindof(a) == MkanyPair)
    @assert(value.a == 11)
    @assert(value.b == 10)
}

#test
{
    var arr: [6] s32 = [1, 2, 3, 4, 5, 6]
    let ptr = cast(*[6] s32) &arr
    let a: any = @mkany(ptr, [6] s32)
    let p = cast(*[6] s32) @dataof(a)
    let value = dref p
    var acc: s32 = 0
    for v, i in value
    {
        acc += v * cast(s32) (i + 1)
    }

    @assert(acc == 91)
}

#test
{
    var x: s32 = 55
    let ptr = cast([*] void) &x
    let a: any = @mkany(ptr, s32)
    let p = cast(*s32) @dataof(a)

    @assert(@kindof(a) == s32)
    @assert(dref p == 55)
}

#test
{
    var k: MkanyKind = MkanyKind.B
    let a: any = @mkany(&k, MkanyKind)
    let p = cast(*MkanyKind) @dataof(a)

    @assert(@kindof(a) == MkanyKind)
    @assert(dref p == MkanyKind.B)
}

#test
{
    var s0: s64 = 10
    var s1: s64 = 20
    var s2: s64 = 30
    var s3: s64 = 40
    var a: any = @mkany(&s0, s64)
    var b: any = @mkany(&s1, s64)
    var c: any = @mkany(&s2, s64)
    var d: any = @mkany(&s3, s64)

    b = a
    c = b
    d = c
    a = @mkany(&s3, s64)
    b = @mkany(&s2, s64)
    c = @mkany(&s1, s64)
    d = @mkany(&s0, s64)

    let p0 = cast(*s64) @dataof(a)
    let p1 = cast(*s64) @dataof(b)
    let p2 = cast(*s64) @dataof(c)
    let p3 = cast(*s64) @dataof(d)

    @assert(cast(u64) (dref p0 + dref p1 + dref p2 + dref p3) == 100'u64)
}

#test
{
    var b: bool = true
    var r: rune = 'A'
    let ab: any = @mkany(&b, bool)
    let ar: any = @mkany(&r, rune)
    let pb = cast(*bool) @dataof(ab)
    let pr = cast(*rune) @dataof(ar)

    @assert(cast(s32) dref pb + cast(s32) dref pr == 66)
}

#test
{
    var boxed: any = null
    var value: s64 = 9000
    boxed = @mkany(&value, s64)
    let p = cast(*s64) @dataof(boxed)

    @assert(@kindof(boxed) == s64)
    @assert(dref p == 9000)
}

#test
{
    var text: string = "alpha"
    let boxed: any = @mkany(&text, string)
    let ptr = cast(*string) @dataof(boxed)

    text = "beta"

    @assert(@kindof(boxed) == string)
    @assert(dref ptr == "beta")
    @assert(@countof(dref ptr) == 4)
    @assert(cast(string) boxed == "beta")
}

func mkanyCastStringFromAny(value: any)->string
{
    let reboxed: any = @mkany(@dataof(value), @kindof(value))
    return cast(string) reboxed
}

func mkanyStringBytesLen(bytes: #null const [..] u8)->u64
{
    return @countof(bytes)
}

func mkanyCastStringToBytesFromAny(value: any)->u64
{
    let reboxed: any = @mkany(@dataof(value), @kindof(value))
    return mkanyStringBytesLen(cast(string) reboxed)
}

#test
{
    @assert(mkanyCastStringFromAny("gamma") == "gamma")
    @assert(mkanyCastStringToBytesFromAny("delta") == 5)
}

#test
{
    var buffer: [4] s32 = [3, 6, 9, 12]
    var values: [..] s32 = buffer
    let boxed: any = @mkany(&values, [..] s32)
    let ptr = cast(*[..] s32) @dataof(boxed)

    values[1] = 77
    values = buffer[1 to 3]

    @assert(@kindof(boxed) == [..] s32)
    @assert(@countof(dref ptr) == 3)
    @assert((dref ptr)[0] == 77)
    @assert((dref ptr)[2] == 12)
}

#test
{
    var x: s32 = 314
    let ptr = cast(MkanyStrictS32Ptr) &x
    let boxed: any = @mkany(ptr, s32)
    let data = cast(*s32) @dataof(boxed)

    @assert(@kindof(boxed) == s32)
    @assert(dref data == 314)
}

#test
{
    var x: s32 = 271
    let ptr = cast(MkanyStrictVoidPtr) &x
    let boxed: any = @mkany(ptr, s32)
    let data = cast(*s32) @dataof(boxed)

    @assert(@kindof(boxed) == s32)
    @assert(dref data == 271)
}

#test
{
    var x: s32 = 812
    let info = cast(MkanyStrictTypeInfo) #typeof(s32)
    let boxed: any = @mkany(&x, info)
    let data = cast(*s32) @dataof(boxed)

    @assert(@kindof(boxed) == s32)
    @assert(dref data == 812)
}

#test
{
    var x = cast(MkanyStrictS32) 409
    let boxed: any = @mkany(&x, MkanyStrictS32)

    @assert(@kindof(boxed) == MkanyStrictS32)
    @assert(cast(MkanyStrictS32) boxed == cast(MkanyStrictS32) 409)
}

#test
{
    var text = "omega"
    let info = #typeof(text)
    let boxed: any = @mkany(&text, info)

    @assert(@kindof(boxed) == #nonull string)
    @assert(cast(#nonull string) boxed == "omega")
}

#test
{
    var value = 733's32
    let ptr: const *s32 = &value
    let boxed = @mkany(ptr, s32)
    let data = cast(const *s32) boxed
    let raw = cast(const *s32) @dataof(boxed)

    @assert(@kindof(boxed) == s32)
    @assert(dref data == 733)
    @assert(dref raw == 733)
}

#test
{
    var value = 123's32
    let ptr: const *s32 = &value
    let boxed: const any = @mkany(ptr, s32)
    let data = cast(const *s32) boxed

    #assert(#typeof(boxed) == const any)
    @assert(dref data == 123)
}

#test
{
    var storage: [3] u8 = [3'u8, 5'u8, 8'u8]
    let bytes: const [..] u8 = cast(const [..] u8) storage
    let boxed = @mkany(&bytes, const [..] u8)
    let view = cast(const [..] u8) boxed

    @assert(@countof(view) == 3)
    @assert(view[0] == 3'u8)
    @assert(view[2] == 8'u8)
}

#test
{
    var storage: [4] u8 = ['a''u8, 'n''u8, 'y''u8, 0]
    let text: const cstring = cast(const cstring) &storage[0]
    let boxed = @mkany(&text, const cstring)
    let view = cast(const cstring) boxed

    @assert(@countof(view) == 3)
    @assert(view[0] == 'a''u8)
    @assert(view[2] == 'y''u8)
}

#test
{
    var storage: [6] u8 = ['b''u8, 'o''u8, 'x''u8, 'e''u8, 'd''u8, 0]
    let text: const cstring = cast(const cstring) &storage[0]
    let boxed: const any = text
    let view = cast(const cstring) boxed

    @assert(@countof(view) == 5)
    @assert(view[0] == 'b''u8)
    @assert(view[4] == 'd''u8)
}
