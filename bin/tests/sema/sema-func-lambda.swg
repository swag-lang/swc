#global internal

#test
{
    var fn: func()
    fn()
    var fn1: func(s: string)
    fn1("test")
}

struct A
{
    fn: func()
}

#test
{
    var a: A
    a.fn()
}

#test
{
    var fn2: func(v: s32) -> s32
    let r = fn2(12)
    #assert(#typeof(r) == s32)
    fn2("12") // swc-expected-error {{sema_err_cannot_cast}}
}

#test
{
    var fn3: func(v: string)
    fn3("ok")
}

func toto(message: string, loc: Swag.SourceCodeLocation)
{
    let cxt = @getcontext()
    cxt.panic(message, loc)
}
