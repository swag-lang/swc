#global fileprivate // swc-option sema-only
#global skip
//var fn = func(x, y: s32) => x + y

var G = 0

func toto()
{
    G = 1
}

var fn = &toto

#test
{
    fn()
    @assert(G == 1)
}
