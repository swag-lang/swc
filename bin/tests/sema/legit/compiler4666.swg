#global fileprivate // swc-option sema-only
#global skip
//#global skip
//#[Swag.PrintBc]
#test
{
    const a: any = null
    const b: any = null
    @assert(a == null)
    @assert(b == null)
}
