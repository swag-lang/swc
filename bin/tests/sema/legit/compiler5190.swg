#global fileprivate // swc-option sema-only
#global skip
#test
{
    let x: any = 5
    @assert(x == s32)
    @assert(x != bool)
}
