#global fileprivate // swc-option sema-only
#global skip
//#global testerror "Err0004"

#[Swag.Overload]
func toto(x: s32) {}
#[Swag.Overload]
func toto(x: s8) {}

#test
{
    toto(0)
}
