#global fileprivate // swc-option suite-test

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

#test
{
    var a: OuterValue
    a.v.x = 5
    let x = a.x
    #assert(#typeof(x) == s32)
    @assert(x == 5)
}

#test
{
    var inner: Inner
    inner.x = 6
    var a: OuterPtr
    a.p = &inner
    let x = a.x
    #assert(#typeof(x) == s32)
    @assert(x == 6)
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

struct Inner2
{
    x: s32
}

struct OuterAmbiguous
{
    using a: Inner
    using b: Inner2
}

