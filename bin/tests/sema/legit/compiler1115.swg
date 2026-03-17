#global fileprivate // swc-option sema-only
#global skip
#test
{
    let x = 5 % 2
    @assert(x == 1)
}
