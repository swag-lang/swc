#global fileprivate // swc-option sema-only
#global skip
#[Swag.Inline]
func toto()
{
    //var a = 0
    return
}

//#[Swag.PrintBc]
#test
{
    //var a = 1
    toto()
    //@assert(a == 1)
}
