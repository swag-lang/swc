#global fileprivate // swc-option sema-only
#global skip
#[Swag.Mixin]
func toto()
{
    let x = 666
}

#test
{
    toto()
    @assert(x == 666)
}
