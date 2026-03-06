#global fileprivate
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
