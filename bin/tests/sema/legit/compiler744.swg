#global fileprivate // swc-option sema-only
#global skip
struct Point
{
    x:     s32 = undefined
    y:     s32 = undefined
}

//#[Swag.PrintBc]
#test
{
    var pt: Point
}
