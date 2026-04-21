#global fileprivate

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
    var fn3: func(v: string)
    fn3("ok")
}

func toto(message: string, loc: Swag.SourceCodeLocation)
{
    let cxt = @getcontext()
    cxt.panic(message, loc)
}
