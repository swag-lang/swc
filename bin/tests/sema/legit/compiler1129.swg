#global fileprivate // swc-option sema-only
#global skip
//#[Swag.PrintBc]
func toto(x: s32) => x

//#[Swag.PrintBc]
#test
{
    var val = toto(1)
}
