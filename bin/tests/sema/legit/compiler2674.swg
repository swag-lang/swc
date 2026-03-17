#global fileprivate // swc-option sema-only
#global skip
func toto(x: s64)->s64 => x

#test
{
    var vv = {1, 2, fct: &toto}
    @assert(vv.fct(10) == 10)
}
