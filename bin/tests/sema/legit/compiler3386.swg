#global fileprivate // swc-option sema-only
#global skip
struct A
{
    fct: func(s32, bool)
}

#test
{
    var v: A
    v.fct = func(x, y)
    {
        var a = y
    }
}
