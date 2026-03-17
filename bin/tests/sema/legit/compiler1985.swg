#global fileprivate // swc-option sema-only
#global skip
#test
{
    let ptr: const *s32 = null
    if ptr
    {
        @assert(false)
    }
}
