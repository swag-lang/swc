#global fileprivate // swc-option sema-only
#global skip
struct AA
{
    x:   s32
}

impl AA
{
    func toto(me, x: s32)
    {
        me.x = x
    }
}
