#global fileprivate // swc-option sema-only
#global skip
#test
{
    var x = 5
    let y = #constref &x
    @assert(#typeof(y) == #type const &s32)
}
