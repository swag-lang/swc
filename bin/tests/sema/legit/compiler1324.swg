#global fileprivate // swc-option sema-only
#global skip
//#global testerror "Err0508"

#[Swag.Macro]
func toto()
{
    #macro
    {
        var cpt = 0
    }
}

//#[Swag.PrintBc]
#test
{
    var cpt = 0
    toto()
}
