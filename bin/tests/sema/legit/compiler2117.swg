#global fileprivate // swc-option sema-only
#global skip
struct(T) Arr
{
    struct ST { x, y: T }
}

//#[Swag.PrintBc]
#test
{
    var x: Arr's32
}
