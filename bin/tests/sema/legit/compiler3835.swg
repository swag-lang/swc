#global fileprivate // swc-option sema-only
#global skip
struct A
{
    x:   s32
}

#test
{
    var v: A
    with v
    {
        var a = &.x
        dref a = 666
        @assert(.x == 666)
    }
}
