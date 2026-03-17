#global fileprivate // swc-option sema-only
#global skip
#test
{
    #[Swag.Mixin]
    func toto()
    {
        var #alias0 = 5
    }

    toto()
}
