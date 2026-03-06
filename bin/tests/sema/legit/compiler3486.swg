#global fileprivate
#global skip
struct A
{
    fct: func||(*A)
}

#test
{
    var v: A
    v.fct = func(s) {}
}
