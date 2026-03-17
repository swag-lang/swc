#global fileprivate // swc-option sema-only
#global skip
#test
{
    let x = #type func()->s32
    @assert(x.fullname == "func()->s32")
}
