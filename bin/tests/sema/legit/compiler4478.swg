#global fileprivate // swc-option sema-only
#global skip
func toto() => 666
#test
{
    var g = 0
    if let x = toto()
    {
        g = x
    }

    @assert(g == 666)
}
