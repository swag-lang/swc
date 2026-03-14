#global fileprivate // swc-option suite-test

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
    foreach v, i in value
    {
        acc += v * cast(s32) (i + 1)
    }

    @assert(acc == 91)
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
