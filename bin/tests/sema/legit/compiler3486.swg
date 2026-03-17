#global fileprivate // swc-option sema-only
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
