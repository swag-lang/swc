#global fileprivate

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
    func mkanyRoundtripS32()->s32
    {
        var x: s32 = 42
        let a: any = @mkany(&x, s32)
        let p = cast(*s32) @dataof(a)
        return dref p
    }

    const V = #run mkanyRoundtripS32()
    #assert(V == 42)
}

#test
{
    func mkanyAssignAny()->s32
    {
        var x: s32 = 123
        var y: s32 = 7
        var a: any = @mkany(&x, s32)
        var b: any = @mkany(&y, s32)
        b = a
        let p = cast(*s32) @dataof(b)
        return dref p
    }

    const V = #run mkanyAssignAny()
    #assert(V == 123)
}

#test
{
    func mkanyKindof()->bool
    {
        var x: s64 = 9000
        let a: any = @mkany(&x, s64)
        return @kindof(a) == s64
    }

    const V = #run mkanyKindof()
    #assert(V)
}

#test
{
    func mkanyRoundtripPair()->s32
    {
        var p: MkanyPair = {a: 11, b: 31}
        let a: any = @mkany(&p, MkanyPair)
        let data = cast(*MkanyPair) @dataof(a)
        let value = dref data
        return value.a + value.b
    }

    const V = #run mkanyRoundtripPair()
    #assert(V == 42)
}

#test
{
    func mkanyRoundtripArray()->s32
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

        return acc
    }

    const V = #run mkanyRoundtripArray()
    #assert(V == 91)
}

#test
{
    func mkanyKindAndValue()->bool
    {
        var k: MkanyKind = MkanyKind.B
        let a: any = @mkany(&k, MkanyKind)
        if @kindof(a) != MkanyKind do
            return false
        let p = cast(*MkanyKind) @dataof(a)
        return dref p == MkanyKind.B
    }

    const V = #run mkanyKindAndValue()
    #assert(V)
}

#test
{
    func mkanyRewriteStress()->u64
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
        return cast(u64) (dref p0 + dref p1 + dref p2 + dref p3)
    }

    const V = #run mkanyRewriteStress()
    #assert(V == 100'u64)
}

#test
{
    func mkanyBoolRuneMix()->s32
    {
        var b: bool = true
        var r: rune = 'A'
        let ab: any = @mkany(&b, bool)
        let ar: any = @mkany(&r, rune)
        let pb = cast(*bool) @dataof(ab)
        let pr = cast(*rune) @dataof(ar)
        return cast(s32) dref pb + cast(s32) dref pr
    }

    const V = #run mkanyBoolRuneMix()
    #assert(V == 66)
}
