#global fileprivate // swc-option sema-only
#global skip
#[Swag.CalleeReturn, Swag.Macro]
func toto()
{
    #[Swag.Safety(.All, .All, true)]
    #macro
    {
        return
    }
}

#test
{
    toto()
    @assert(false)
}
