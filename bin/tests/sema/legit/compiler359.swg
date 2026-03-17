#global fileprivate // swc-option sema-only
#global skip
var a = [1, 2]

//#[Swag.PrintBc]
#test
{
    let ptr1 = &a
    @assert(ptr1[0] == 1)
    @assert(ptr1[1] == 2)
}
