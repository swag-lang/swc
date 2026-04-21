#global fileprivate

func TakeMatrix2(v: [2, 2] s32) {}

#test
{
    const values: [4] s32 = [1, 2, 3, 4]
    TakeMatrix2(values) // swc-expected-error {{sema_err_array_cast_num_dims}}
}
