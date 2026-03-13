#global fileprivate // swc-option suite-test

#test
{
    var fn: func() = null
    var fn1: func(s: string) = null
    #assert(#nameof(#typeof(fn)) == "func()")
    #assert(#nameof(#typeof(fn1)) == "func(s: string)")
}

struct A
{
    fn: func()
}

#test
{
    var a: A
    a.fn = null
    #assert(#nameof(#typeof(a.fn)) == "func()")
}

#test
{
    var fn2: func(v: s32) -> s32 = null
    #assert(#nameof(#typeof(fn2)) == "func(v: s32)->s32")
    fn2("12") // swc-expected-error {{sema_err_cannot_cast}}
}

#test
{
    var fn3: func(v: string) = null
    #assert(#nameof(#typeof(fn3)) == "func(v: string)")
}

func toto(message: string, loc: Swag.SourceCodeLocation)
{
    let cxt = @getcontext()
    cxt.panic(message, loc)
}
