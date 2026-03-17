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
    var pt: Point{1, 2}
    //pt.x = 0
}
