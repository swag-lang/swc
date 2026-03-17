#global fileprivate // swc-option sema-only
#global skip
#[Swag.Optimize(.All, false)]
func(T) toto(y: T)->T
{
    var x = y
    x %= 3
    return x
}

#test
{
    @assert(toto's8(6) == 0)
    @assert(toto's8(5) == 2)
}
