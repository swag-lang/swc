#global private

func semaTest001()
{
    var fn: #null func()
    fn()
    var fn1: #null func(s: string)
    fn1("test")
}

struct A
{
    fn: #null func()
}

func semaTest002()
{
    var a: A
    a.fn()
}

func semaTest003()
{
    var fn3: #null func(v: string)
    fn3("ok")
}

func toto(message: string, loc: Swag.SourceCodeLocation)
{
    let cxt = @getcontext()
    cxt.panic(message, loc)
}
