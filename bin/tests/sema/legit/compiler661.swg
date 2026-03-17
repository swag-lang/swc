#global fileprivate // swc-option sema-only
#global skip
enum OT
{
    A = 1
    B
}

//#[Swag.PrintBc]
//#global testerror
#test
{
    var pt = {x: OT.A}
}
