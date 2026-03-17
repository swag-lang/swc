#global fileprivate // swc-option sema-only
#global skip
func F(a: string = "toto")
{
    @assert(a == "toto")
}

//#[Swag.PrintBc]
#test
{
    F()
}
