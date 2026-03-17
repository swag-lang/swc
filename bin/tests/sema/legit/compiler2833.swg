#global fileprivate // swc-option sema-only
#global skip
#test
{
    let x = 1'u32
    let y = -cast(s64) x
    @assert(y == -1)
}
