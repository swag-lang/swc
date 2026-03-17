#global fileprivate // swc-option sema-only
#global skip
struct Point
{
    x:   s32 = 666
}

//#[Swag.PrintBc]
#test
{
    var pt:    Point
    let slice: *Point = &pt
    @assert(slice.x == 666)
}
