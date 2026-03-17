#global fileprivate // swc-option sema-only
#global skip
func(T) toto(x, y: T)
{
    @assert(#typeof(x) == #typeof(f32))
}

#test
{
    toto'f32(1, 2)
}
