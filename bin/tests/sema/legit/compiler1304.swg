#global fileprivate // swc-option sema-only
#global skip
#[Swag.Macro]
func toto(t: s32)
{
    @assert(t == 100)
}

#test
{
    toto(100)
}
