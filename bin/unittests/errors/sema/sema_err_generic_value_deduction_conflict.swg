#global fileprivate

func(const N: s32) genericZip(lhs: [N] s32, rhs: [N] s32) {}

#test
{
    const lhs: [2] s32 = [1, 2]
    const rhs: [3] s32 = [3, 4, 5]
    genericZip(lhs, rhs) // swc-expected-error {{sema_err_generic_value_deduction_conflict}}
}
