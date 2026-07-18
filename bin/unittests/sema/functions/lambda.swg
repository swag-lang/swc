#global private
#global #[Swag.ExplicitNullability]

func semaTest001()
{
    var fn: func()
    fn()
    var fn1: func(s: #nonull string)
    fn1("test")
}

struct A
{
    fn: func()
}

func semaTest002()
{
    var a: A
    a.fn()
}

func semaTest003()
{
    var fn3: func(v: #nonull string)
    fn3("ok")
}

func toto(message: #nonull string, loc: Swag.SourceCodeLocation)
{
    let cxt = @getcontext()
    cxt.panic(message, loc)
}
