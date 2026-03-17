#global fileprivate // swc-option sema-only
#global skip
//#global testerror "Err0025"
#test
{
    var x = 5
    var y = #constref &x
    y = #constref &x
}
