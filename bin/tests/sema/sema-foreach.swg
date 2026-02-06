#global internal

#test
{
    var arr: [3] s32 = [1, 2, 3]
    foreach v in arr
    {
        #assert(#typeof(v) == s32)
        var x = v
    }
}

#test
{
    var arr: [2] s32 = [1, 2]
    foreach v, i in arr
    {
        #assert(#typeof(v) == s32)
        #assert(#typeof(i) == u64)
        var x = v
        var y = i
    }

    var z = v // swc-expected-error {{sema_err_unknown_symbol}}
}

#test
{
    var arr: [2] s32 = [1, 2]
    foreach v in arr where v > 0
    {
        var x = v
    }
}

#test
{
    var arr: [2] s32 = [1, 2]
    foreach v, i, j in arr {} // swc1-expected-error {{sema_err_foreach_too_many_names}}
}

#test
{
    var arr: [2] u32 = [10'u32, 20]
    foreach &v in arr
    {
        var x = dref v
    }
}

#test
{
    foreach v in 12 {} // swc-expected-error {{sema_err_type_not_indexable}}
}

#test
{
    var arr: [1] s32 = [1]
    foreach v in arr where s32 {} // swc-expected-error {{sema_err_not_value_expr}}
}
