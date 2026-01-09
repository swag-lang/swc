#global internal

#test
{
    var buf1: [4] s32
    var a1 = buf1[0]
    #assert(#typeof(a1) == s32)

    var ptr1 = &buf1[0]
    #assert(#typeof(ptr1) == *s32)
}

#test
{
    var a2: [2, 2] s32
    var b2 = a2[0, 0, 0] // swc-expected-error {{sema_err_array_num_dims}}
}

#test
{
    var a3: [2, 2] s32
    var b3 = a3[0, 0.0] // swc-expected-error {{sema_err_array_dim_not_int}}
}

#test
{
    var a4: [2, 3] s32
    #assert(#typeof(a4[0]) == #type [3] s32)
}

#test
{
    var a5 = 0
    var b5 = a5[0] // swc-expected-error {{sema_err_type_not_indexable}}
}

#test
{
    var a6: [..] s32
    var b6 = a6[0]
    #assert(#typeof(b6) == s32)
}

#test
{
    var a7: [..] s32
    var b7 = a7[0, 0] // swc-expected-error {{sema_err_array_num_dims}}
}

#test
{
    var a1 = 0
    var b1 = a1[0] // swc-expected-error {{sema_err_type_not_indexable}}
}

#test
{
    var a2: [..] s32
    var b2 = a2[0]
    #assert(#typeof(b2) == s32)
}

#test
{
    var a3: [..] s32
    var b3 = a3[0, 0] // swc-expected-error {{sema_err_array_num_dims}}
}
