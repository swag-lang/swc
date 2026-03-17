#global fileprivate // swc-option sema-only
#global skip
struct X
{
    x:   s32
}

func toto()->X
{
    return {x: 666}
}

#test
{
    @assert(toto().x == 666)
}
