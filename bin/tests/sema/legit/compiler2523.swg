#global fileprivate // swc-option sema-only
#global skip
//#[Swag.PrintBc]
#test
{
    let x = "toto"
    if x == null
    {
        @assert(false)
    }
}
