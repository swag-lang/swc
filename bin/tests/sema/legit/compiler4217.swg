#global fileprivate // swc-option sema-only
#global skip
var G = 0

func titi()
{
    G = 1
}

#[Swag.Inline]
func toto() => titi()

#test
{
    toto()
    @assert(G == 1)
}
