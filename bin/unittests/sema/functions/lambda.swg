#global private

func semaTest001()
{
    var fn: (func())?
    if fn
    {
        fn()
    }
    var fn1: (func(s: string))?
    if fn1
    {
        fn1("test")
    }
}

struct A
{
    fn: (func())?
}

func semaTest002()
{
    var a: A
    if a.fn
    {
        a.fn()
    }
}

func semaTest003()
{
    var fn3: (func(v: string))?
    if fn3
    {
        fn3("ok")
    }
}

func toto(message: string, loc: Swag.SourceCodeLocation)
{
    let cxt = Swag.getContext()
    if cxt.panic
    {
        cxt.panic(message, loc)
    }
}
