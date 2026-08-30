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

#test
{
    func mkanyRoundtripS32()->s32
    {
        var x: s32 = 42
        let a: any = Swag.makeAny(&x, s32)
        let p      = cast(*s32) a.buffer
        return p[]
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
        var a: any = Swag.makeAny(&x, s32)
        var b: any = Swag.makeAny(&y, s32)
        b = a
        let p = cast(*s32) b.buffer
        return p[]
    }

    const V = #run mkanyAssignAny()
    #assert(V == 123)
}

#test
{
    func mkanyKindof()->bool
    {
        var x: s64 = 9000
        let a: any = Swag.makeAny(&x, s64)
        return Swag.kindOf(a) == s64
    }

    const V = #run mkanyKindof()
    #assert(V)
}

#test
{
    func mkanyRoundtripPair()->s32
    {
        var p: MkanyPair = {a: 11, b: 31}
        let a: any       = Swag.makeAny(&p, MkanyPair)
        let data         = cast(*MkanyPair) a.buffer
        let value        = data[]
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
        let ptr          = cast(*[6] s32) &arr
        let a:   any     = Swag.makeAny(ptr, [6] s32)
        let p            = cast(*[6] s32) a.buffer
        let value        = p[]
        var acc: s32     = 0
        for v, i in value
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
    func mkanyBlockVoidPointer()->s32
    {
        var x: s32 = 55
        let ptr    = cast([*] void) &x
        let a: any = Swag.makeAny(ptr, s32)
        let p      = cast(*s32) a.buffer
        return p[]
    }

    const V = #run mkanyBlockVoidPointer()
    #assert(V == 55)
}

#test
{
    func mkanyKindAndValue()->bool
    {
        var k: MkanyKind = MkanyKind.B
        let a: any       = Swag.makeAny(&k, MkanyKind)
        if Swag.kindOf(a) != MkanyKind do
            return false
        let p = cast(*MkanyKind) a.buffer
        return p[] == MkanyKind.B
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
        return cast(u64) (p0[] + p1[] + p2[] + p3[])
    }

    const V = #run mkanyRewriteStress()
    #assert(V == 100'u64)
}

#test
{
    func mkanyCastStringFromAny(value: any)->string
    {
        let reboxed: any = Swag.makeAny(value.buffer, Swag.kindOf(value))
        return cast(string) reboxed
    }

    const V = #run mkanyCastStringFromAny("gamma")
    #assert(V == "gamma")
}

#test
{
    func mkanyStringBytesLen(bytes: #null const [..] u8)->u64
    {
        return bytes.count
    }

    func mkanyCastStringToBytesFromAny(value: any)->u64
    {
        let reboxed: any = Swag.makeAny(value.buffer, Swag.kindOf(value))
        return mkanyStringBytesLen(cast(string) reboxed)
    }

    const V = #run mkanyCastStringToBytesFromAny("delta")
    #assert(V == 5)
}

#test
{
    func mkanyBoolRuneMix()->s32
    {
        var b:  bool = true
        var r:  rune = 'A'
        let ab: any  = Swag.makeAny(&b, bool)
        let ar: any  = Swag.makeAny(&r, rune)
        let pb       = cast(*bool) ab.buffer
        let pr       = cast(*rune) ar.buffer
        return cast(s32) pb[] + cast(s32) pr[]
    }

    const V = #run mkanyBoolRuneMix()
    #assert(V == 66)
}

#test
{
    func mkanyStoredTypeValueArray()->f32
    {
        var values     = [1, 2.5]
        let info       = #typeof(values)
        let boxed: any = Swag.makeAny(&values, info)
        let data       = cast(*[2] f32) boxed.buffer
        let array      = data[]
        return array[0] + array[1]
    }

    const V = #run mkanyStoredTypeValueArray()
    #assert(V == 3.5)
}
