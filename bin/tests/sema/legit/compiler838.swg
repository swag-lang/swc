#global fileprivate // swc-option sema-only
#global skip
//#[Swag.PrintBc]
#test
{
    let i = 0
    while (i < 0)
    {
        @assert(false)
    }
}
