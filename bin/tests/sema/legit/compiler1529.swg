#global fileprivate // swc-option sema-only
#global skip
struct(T) Array {}

impl Array
{
    func add(me, value: T) {}
}

//#[Swag.PrintBc]
#test
{
    var arr: Array's32
    arr.add(666)
}
