#global fileprivate // swc-option sema-only
#global skip
//#[Swag.PrintBc]
#test
{
    const a = 6
    let b   = a
    @assert(b == 6)
    @assert(b == a)
}
