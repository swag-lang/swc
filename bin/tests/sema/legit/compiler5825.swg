#global fileprivate // swc-option sema-only
#global skip
//#[Swag.PrintBc]
func toto(y: u32)
{
    let z = y << 33
    @assert(z == 0)
}

#test
{
    toto(1)
}
