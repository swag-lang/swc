#global fileprivate // swc-option sema-only
#global skip
struct A
{
    x:   s32
}

func titi()
{
    var pt: A
    var y   = pt.x
}
