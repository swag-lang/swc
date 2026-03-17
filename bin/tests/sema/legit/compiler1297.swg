#global fileprivate // swc-option sema-only
#global skip
#[Swag.Macro]
func toto(x: #code void)
{
    #macro
    {
        #inject(#up x)
    }
}

#test
{
    var a = 0
    toto()
    {
        a = 666
    }
    @assert(a == 666)
}
