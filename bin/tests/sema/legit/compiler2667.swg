#global fileprivate // swc-option sema-only
#global skip
#[Swag.Macro]
func toto()
{
    let a = 0
    switch a
    {
    case 0:
        var b = 1
    case 1:
        var b = 1
    }
}

#test
{
    toto()
}
