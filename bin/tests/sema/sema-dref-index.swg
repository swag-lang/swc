#global internal

#test
{
    var buf: [4] s32
    var a = buf[0]
    #assert(#typeof(a) == s32)

    var ptr = &buf[0]
    #assert(#typeof(ptr) == *s32)
}

#test
{
    var a: [2, 2] s32;
    var b = a[0, 0, 0] // swc-expected-error {{sema_err_array_num_dims}}
}

#test
{
    var a: [2, 2] s32;
    var b = a[0, 0.0] // swc-expected-error {{sema_err_array_dim_not_int}}
}
