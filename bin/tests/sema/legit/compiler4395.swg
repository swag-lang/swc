#global fileprivate // swc-option sema-only
#global skip
func toto(x: typeinfo) {}

//#[Swag.PrintBc]
#test
{
    toto(#type [2] s32)
}
