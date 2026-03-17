#global fileprivate // swc-option sema-only
#global skip
#[Swag.Inline]
func toto()
{
    let x = #nameof(toto)
    @assert(x == "toto")
}

#test
{
    toto()
}
