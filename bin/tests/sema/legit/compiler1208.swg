#global fileprivate // swc-option sema-only
#global skip
#[Swag.Inline]
//public
{
    func toto()
    {
        //@print("toto")
    }
}

//#[Swag.PrintBc]
#test
{
    toto()
}
