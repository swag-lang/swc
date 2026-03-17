#global fileprivate // swc-option sema-only
#global skip
//#[Swag.PrintBc]
func(op: string) toto() {}

//#[Swag.PrintBc]
#test
{
    toto'("op")()
    toto'("op1")()
    toto'("op")()
}
