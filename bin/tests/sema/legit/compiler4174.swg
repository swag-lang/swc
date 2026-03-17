#global fileprivate // swc-option sema-only
#global skip
#[Swag.Safety(.All, .All, true)]
func toto()->s32
{
    let x = 1
    var y = 2
    y *= x
    var z = 4
    z /= y
    return z
}

#test
{
    @assert(toto() == 2)
}
