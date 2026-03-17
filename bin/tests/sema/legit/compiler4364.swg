#global fileprivate // swc-option sema-only
#global skip
const A = 2's8

func toto(x: s8) {}

#test
{
    toto(A)
}
