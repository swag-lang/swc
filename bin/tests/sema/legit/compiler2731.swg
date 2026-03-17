#global fileprivate // swc-option sema-only
#global skip
var G = 0
func toto()
{
    defer #err G = 1
}

#test
{
    toto()
    @assert(G == 0)
}
