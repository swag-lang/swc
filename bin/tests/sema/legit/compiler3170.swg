#global fileprivate // swc-option sema-only
#global skip
struct AAA
{
    v    = 666
}

func toto(xxx: AAA = {555})
{
    @assert(xxx.v == 555)
}

#test
{
    toto()
}
