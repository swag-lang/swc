#global private

#test
{
    const K: [4] s32 = [10, 20, 30, 40]
    var L: [3] s32 = K     // swc-expected-error {{sema_err_array_cast_dim_mismatch}}
}

#test
{
    var x = [1, 2]
    var y = [3, 4, 5]
    var N: [2] [2] s32 = [x, y]     // swc-expected-error {{sema_err_array_cast_dim_mismatch}}
}

alias ArrayCastDimMismatchDigest = [16] u8

func consumeArrayCastDimMismatch4(values: [4] s32) {}

func consumeArrayCastDimMismatchDigest(digest: ArrayCastDimMismatchDigest) {}

func consumeArrayCastDimMismatchGrid(grid: [2, 3] s16) {}

#test
{
    var wrong: [3] s32 = [1, 2, 3]
    consumeArrayCastDimMismatch4(wrong)     // swc-expected-error {{sema_err_array_cast_dim_mismatch}}
}

#test
{
    var wrong: [15] u8 = undefined
    consumeArrayCastDimMismatchDigest(wrong)     // swc-expected-error {{sema_err_array_cast_dim_mismatch}}
}

#test
{
    var wrong: [2, 2] s16 = [[1, 2], [3, 4]]
    consumeArrayCastDimMismatchGrid(wrong)     // swc-expected-error {{sema_err_array_cast_dim_mismatch}}
}
