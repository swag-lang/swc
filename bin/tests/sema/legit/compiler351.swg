#global fileprivate // swc-option sema-only
#global skip
//#[Swag.PrintBc]
#test
{
    var a = [0, 1]
    @assert(a[0] == 0)
    @assert(a[1] == 1)
}
