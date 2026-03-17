#global fileprivate // swc-option sema-only
#global skip
struct A
{
    x:   s32
}

#test
{
    var t: A
    t.x = 0
}
