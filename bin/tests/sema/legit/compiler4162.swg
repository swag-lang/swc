#global fileprivate // swc-option sema-only
#global skip
//#global testerror

//#[Swag.PrintBc]
#[Swag.Optimize(.All, false), Swag.Sanity(true)]
func toto()
{
    var f0, f1: f32 = 0
    f0, f1 = 0
}
