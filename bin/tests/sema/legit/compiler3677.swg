#global fileprivate // swc-option sema-only
#global skip
#[Swag.Macro]
func toto(stmt: #code void)
{
    #inject(stmt)
}

//#[Swag.PrintBc]
#test
{
    toto()
    {
        struct A {}
        var x: A
        //var x = func(){}
        //x()
    }
}
