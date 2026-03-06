#global fileprivate
#global skip
#test
{
    let ptr: const *s32 = null
    if ptr
    {
        @assert(false)
    }
}
