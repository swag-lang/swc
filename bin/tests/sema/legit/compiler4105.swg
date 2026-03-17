#global fileprivate // swc-option sema-only
#global skip
//#global testerror
using Swag

#test
{
    let b = false
    var x = b ? "toto" : null
}
