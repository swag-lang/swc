#global fileprivate // swc-option sema-only
#global skip
#[Swag.Macro]
func toto(x, y: s64 = 666)
{
    @assert(x == 666)
    @assert(y == 444)
}

//#[Swag.PrintBc]//, Swag.Optimize(.All, false)]
#test
{
    toto(y: 444)
}
