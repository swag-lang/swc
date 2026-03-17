#global fileprivate // swc-option sema-only
#global skip
interface I
{
    func toto(me);
}

//#[Swag.PrintBc]
#test
{
    var a, b: I
    @assert(a == b)
}
