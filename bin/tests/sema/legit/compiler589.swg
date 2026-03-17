#global fileprivate
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
