#global fileprivate // swc-option sema-only
#global skip
#[Swag.Inline]
func toto()
{
    let b = 666
    return
}

//#[Swag.PrintBc]
#test
{
    let a = 1
    toto()
    @assert(a == 1)
}
