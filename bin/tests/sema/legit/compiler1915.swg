#global fileprivate // swc-option sema-only
#global skip
//#[Swag.PrintBc]
#test
{
    let a = 1'u64
    @assert(a == 1)
}
