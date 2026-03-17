#global fileprivate // swc-option sema-only
#global skip
func(T) toto(x: T)
{
    @assert(#typeof(x) == f32)
}

#test
{
    toto'f32(1)
}
