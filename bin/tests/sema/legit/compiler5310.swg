#global fileprivate // swc-option sema-only
#global skip
#global skip

//#global testerror "Err0014"

#[Swag.Optimize(.All, false)]
#test
{
    var a: [1000,1000] bool
}
