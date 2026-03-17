#global fileprivate // swc-option sema-only
#global skip
struct(T) Arr
{
    struct ST1
    {
        x:   T
    }

    z:   ST1
}

//#[Swag.PrintBc]
#test
{
    var x: Arr'f64
    @assert(#typeof(x.z.x) == f64)
}
