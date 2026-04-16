#global fileprivate

struct(T) FloatPoint
    where T == f32 or T == f64
{
    x, y: T
}

#test
{
    let point: FloatPoint'f64 = {x: 1.0, y: 2.0}
    #assert(#typeof(point.x) == f64)
}

#test
{
    let bad: FloatPoint's32 // swc-expected-error {{sema_err_generic_struct_where_failed}}
}
