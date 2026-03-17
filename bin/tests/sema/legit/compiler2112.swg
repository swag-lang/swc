#global fileprivate // swc-option sema-only
#global skip
//#[Swag.PrintBc]
#test
{
    var x = {"toto", true}
    var (name, ?) = x
    (name, ?) = x
}
