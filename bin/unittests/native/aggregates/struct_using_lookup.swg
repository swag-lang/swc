#global private

struct Inner
{
    x: s32
}

#[Swag.Strict]
alias StructUsingStrictInnerPtr = #null *Inner

struct OuterValue
{
    using v: Inner
}

struct OuterPtr
{
    using p: #null *Inner
}

struct OuterStrictPtr
{
    using p: StructUsingStrictInnerPtr
}

struct OuterAnonymousStruct
{
    using data: struct
    {
        x: s32
        y: s32
    }
}

struct OuterAnonymousUnion
{
    using data: union
    {
        bytes: [8] u8
        words: [2] u32
    }
}

#test
{
    var a: OuterValue
    a.v.x = 5
    let x = a.x
    #assert(#typeof(x) == s32)
    Swag.assert(x == 5)
}

#test
{
    var inner: Inner
    inner.x = 6
    var a: OuterPtr
    a.p = &inner
    let x = a.x
    #assert(#typeof(x) == s32)
    Swag.assert(x == 6)
}

#test
{
    var inner: Inner
    inner.x = 8
    var a: OuterStrictPtr
    a.p = cast(StructUsingStrictInnerPtr) &inner
    let x = a.x
    #assert(#typeof(x) == s32)
    Swag.assert(x == 8)
}

#test
{
    var s: OuterAnonymousStruct
    s.x = 4
    s.y = 9
    Swag.assert(s.data.x == 4)
    Swag.assert(s.data.y == 9)
}

#test
{
    var u: OuterAnonymousUnion
    u.bytes[0] = 0x2A
    Swag.assert(u.data.bytes[0] == 0x2A)

    u.words[1] = 0x11223344
    Swag.assert(u.data.words[1] == 0x11223344)
}

#test
{
    var innerVal: Inner
    var out:      OuterValue
    out.x = 7
    Swag.assert(out.v.x == 7)

    var outPtr: OuterPtr
    outPtr.p = &innerVal
    outPtr.x = 9
    Swag.assert(innerVal.x == 9)
}

#test
{
    var out: OuterValue
    out.x = 11

    let basePtr: const *Inner = &out
    Swag.assert(basePtr.x == 11)

    let baseRef: const *Inner = &out
    Swag.assert(baseRef.x == 11)
}

struct Inner2
{
    x: s32
}

struct OuterAmbiguous
{
    using a: Inner
    using b: Inner2
}
