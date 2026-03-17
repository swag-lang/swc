#global fileprivate // swc-option sema-only
#global skip
//#[Swag.PrintBc]
func toto()->#null any
{
    return null
}

//#[Swag.PrintBc]
#test
{
    let x = toto()
    @assert(x == null)
}
