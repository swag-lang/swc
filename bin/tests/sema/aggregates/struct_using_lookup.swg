#global fileprivate

struct Inner
{
    x: s32
}

struct OuterValue
{
    using v: Inner
}

struct OuterPtr
{
    using p: *Inner
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
    let x = a.x
    #assert(#typeof(x) == s32)
}

#test
{
    var a: OuterPtr
    let x = a.x
    #assert(#typeof(x) == s32)
}

#test
{
    var s: OuterAnonymousStruct
    #assert(#typeof(s.x) == s32)
    #assert(#typeof(s.y) == s32)
    #assert(#typeof(s.data.x) == s32)
}

#test
{
    var u: OuterAnonymousUnion
    #assert(#typeof(u.bytes) == #type [8] u8)
    #assert(#typeof(u.words) == #type [2] u32)
    #assert(#typeof(u.data.words) == #type [2] u32)
}

#test
{
    var innerVal: Inner
    var out: OuterValue
    out.x = 7
    @assert(out.v.x == 7)

    var outPtr: OuterPtr
    outPtr.p = &innerVal
    outPtr.x = 9
    @assert(innerVal.x == 9)
}

#test
{
    var out: OuterValue
    out.x = 11

    let basePtr: const *Inner = &out
    #assert(#typeof(basePtr) == const *Inner)

    let baseRef: const &Inner = &out
    #assert(#typeof(baseRef) == const &Inner)
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
