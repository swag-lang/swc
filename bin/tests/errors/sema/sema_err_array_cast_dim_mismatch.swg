#global fileprivate

#test
{
    const K: [4] s32 = [10, 20, 30, 40]
    var L: [3] s32 = K // swc-expected-error {{sema_err_array_cast_dim_mismatch}}
}

#test
{
    var x = [1, 2]
    var y = [3, 4, 5]
    var N: [2] [2] s32 = [x, y] // swc-expected-error {{sema_err_array_cast_dim_mismatch}}
}
