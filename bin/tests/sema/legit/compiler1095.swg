#global fileprivate // swc-option sema-only
#global skip
#test
{
    let x = 1
    @assert(x & 1 != 0)
}
