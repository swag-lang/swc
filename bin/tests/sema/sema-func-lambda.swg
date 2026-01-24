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