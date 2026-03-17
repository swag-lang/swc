#global fileprivate // swc-option sema-only
#global skip
//#global testerror

enum OT
{
    A = 1
    B
}

//#[Swag.PrintBc]
#test
{
    var pt: [1] OT
}
