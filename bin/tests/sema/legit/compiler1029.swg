#global fileprivate // swc-option sema-only
#global skip
//#[Swag.PrintBc]
#test
{
    var x = 10
    @init(&x, 1)(0)
    @assert(x == 0)
}
