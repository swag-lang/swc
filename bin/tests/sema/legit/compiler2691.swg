#global fileprivate // swc-option sema-only
#global skip
#test
{
    let x = 1's64 / 2'f64
    #assert(#typeof(x) == f64)
}
