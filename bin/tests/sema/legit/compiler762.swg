#global fileprivate // swc-option sema-only
#global skip
struct Point
{
    x:     s32
    y:     s32
}

//#[Swag.PrintBc]
#test
{
    let cpt = Point
    @assert(cpt == Point)
}
