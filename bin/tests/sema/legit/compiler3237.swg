#global fileprivate // swc-option sema-only
#global skip
#test
{
    @assert(#stringof(s32) == "s32")
    @assert(#nameof(s32) == "s32")
}
