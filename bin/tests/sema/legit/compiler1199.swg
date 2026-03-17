#global fileprivate // swc-option sema-only
#global skip
struct E
{
    x:   s32
}

#test
{
    var ptr = #typeof(E.x)
}
