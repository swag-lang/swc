#global fileprivate // swc-option sema-only
#global skip
//#global testerror "Err0604"

#[Swag.Overload]
func toto(x: s32) {}

#test
{
    toto(0's8)
}
