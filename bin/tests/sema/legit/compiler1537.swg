#global fileprivate // swc-option sema-only
#global skip
struct(T) toto
{
    x:   T
}

#test
{
    var x: toto'bool
}
