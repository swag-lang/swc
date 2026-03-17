#global fileprivate // swc-option sema-only
#global skip
struct Point {}

impl Point
{
    func opDrop(me) {}
}

//#[Swag.PrintBc]
#test
{
    var pt: Point
}
