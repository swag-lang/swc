#global fileprivate // swc-option sema-only
#global skip
struct point
{
    x:   s32 = 666
}

//#[Swag.PrintBc]
#test
{
    var arr: point
    let ptr  = &arr
    @assert(ptr.x == 666)
}
