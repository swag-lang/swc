#global fileprivate // swc-option sema-only
#global skip
func titi()
{
    //@print("x")
}

//#[Swag.PrintBc]
#test
{
    let fn = &titi
    fn()
}
