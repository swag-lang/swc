#global fileprivate // swc-option sema-only
#global skip
#test
{
    let x, y = 666
    @assert(x == 666)
    @assert(y == 666)
}
