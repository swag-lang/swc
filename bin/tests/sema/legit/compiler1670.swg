#global fileprivate // swc-option sema-only
#global skip
#test
{
    var x: [2] s32
    @assert(#typeof(x[0]).fullname == "s32")
}
