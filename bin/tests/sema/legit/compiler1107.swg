#global fileprivate // swc-option sema-only
#global skip
func(T) toto(x: T)
{
    @assert(#typeof(x) == s64)
}

#test
{
    toto's64(1)
}
