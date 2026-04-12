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

#test
{
    var a: OuterAmbiguous
    let x = a.x // swc-expected-error {{sema_err_ambiguous_symbol}}
}
