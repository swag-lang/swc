#global fileprivate // swc-option sema-only
#global skip
func toto(x: s32)
{
    let y = x
    @assert(y == 10)
}

#test
{
    toto(10)
}
