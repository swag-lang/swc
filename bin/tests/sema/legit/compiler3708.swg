#global fileprivate // swc-option sema-only
#global skip
//#[Swag.PrintBc]
func toto(x: any) {}

#test
{
    toto({})
}
