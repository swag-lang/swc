#global private

func semaTest001()
{
    var fn: #null func()
    if fn do
        fn()
    var fn1: #null func(s: string)
    if fn1 do
        fn1("test")
}

struct A
{
    fn: #null func()
}

func semaTest002()
{
    var a: A
    if a.fn do
        a.fn()
}

func semaTest003()
{
    var fn3: #null func(v: string)
    if fn3 do
        fn3("ok")
}

func toto(message: string, loc: Swag.SourceCodeLocation)
{
    let cxt = @getcontext()
    if cxt.panic do
        cxt.panic(message, loc)
}
