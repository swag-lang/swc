#global fileprivate

func TakeArrayU32(v: [2] u32) {}

#test
{
    const values: [2] s32 = [1, 2]
    TakeArrayU32(values) // swc-expected-error {{sema_err_array_cast_expected_aggregate_constant}}
}
