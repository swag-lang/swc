#global fileprivate

#test
{
    const A: [4] s32 = [1's32, 2, 3, 4]
    A[0] = 0 // swc-expected-error {{sema_err_assign_not_lvalue}}
}
