#global private

func semaTest001()
{
    var fn: (func())?
    if fn do
        fn()
    var fn1: (func(s: string))?
    if fn1 do
        fn1("test")
}

struct A
{
    fn: (func())?
}

func semaTest002()
{
    var a: A
    if a.fn do
        a.fn()
}

func semaTest003()
{
    var fn3: (func(v: string))?
    if fn3 do
        fn3("ok")
}

func toto(message: string, loc: Swag.SourceCodeLocation)
{
    let cxt = Swag.getContext()
    if cxt.panic do
        cxt.panic(message, loc)
}
