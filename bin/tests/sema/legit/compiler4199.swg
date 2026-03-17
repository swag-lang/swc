#global fileprivate // swc-option sema-only
#global skip
#[Swag.Overload]
func toto(x: s32) {}

#[Swag.Inline, Swag.Overload]
func toto()
{
    let x = #nameof(toto)
    @assert(x == "toto")
}

#test
{
    toto()
}
