#global fileprivate // swc-option sema-only
#global skip
#test
{
    const x = #typeof(func()->s32)
    #assert(x == #type func()->s32)
}
