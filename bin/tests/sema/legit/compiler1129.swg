#global fileprivate
#global skip
//#[Swag.PrintBc]
func toto(x: s32) => x

//#[Swag.PrintBc]
#test
{
    var val = toto(1)
}
