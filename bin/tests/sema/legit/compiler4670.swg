#global fileprivate // swc-option sema-only
#global skip
//#global skip
//#[Swag.PrintBc]
#test
{
    const a: const [..] s32 = null
    @assert(a == null)
}
