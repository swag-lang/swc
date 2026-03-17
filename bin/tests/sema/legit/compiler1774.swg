#global fileprivate // swc-option sema-only
#global skip
interface A
{
    func x(me);
}

struct X {}

impl A for X
{
    func impl x(me) {}
}

//#[Swag.PrintBc]
#test
{
    var v: X
    let x: A = v

    @assert(x != null)
}
