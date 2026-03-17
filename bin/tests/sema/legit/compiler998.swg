#global fileprivate // swc-option sema-only
#global skip
using Swag

#test
{
    let x = 6
    @assert(#typeof(x) == s32)
    @assert(#typeof(6.0) == f32)
    @assert(#typeof(6) == s32)
    @assert(#typeof("6") == string)
}
