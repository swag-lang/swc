#global fileprivate // swc-option sema-only
#global skip
#test
{
    var a: s32
    struct A
    {
        x:   #decltype(a)
    }
}
