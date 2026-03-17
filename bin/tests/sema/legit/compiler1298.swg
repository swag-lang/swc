#global fileprivate // swc-option sema-only
#global skip
#[Swag.Macro]
func toto()
{
    var x = 0
    #macro
    {
        var x = 0
    }
}

#test
{
    toto()
}
