#global fileprivate // swc-option sema-only
#global skip
#test
{
    let x = 1 + 2'u64
    @assert(#typeof(x) == u64)
}
