#global internal

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
