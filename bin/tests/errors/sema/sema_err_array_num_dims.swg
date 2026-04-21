#global fileprivate

#test
{
    var a2: [2, 2] s32
    var b2 = a2[0, 0, 0] // swc-expected-error {{sema_err_array_num_dims}}
}

#test
{
    var a7: [..] s32
    var b7 = a7[0, 0] // swc-expected-error {{sema_err_array_num_dims}}
}
