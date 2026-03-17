#global fileprivate // swc-option sema-only
#global skip
struct AA
{
    using params: union
    {
        x:     s32
        y:     bool
    }
}

#test
{
    var v: AA
    v.y = true
}
