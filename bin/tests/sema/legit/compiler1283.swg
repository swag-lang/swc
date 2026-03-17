#global fileprivate // swc-option sema-only
#global skip
//#[Swag.PrintBc]
#test
{
    var a = 1

    func toto()
    {
        var a = 2
    }
}
