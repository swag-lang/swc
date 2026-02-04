#global internal

#test
{
    var a: s32
    a /= 0 // swc-expected-error {{sema_err_division_zero}}
}

#test
{
    var a: s32
    a %= (1-1) // swc-expected-error {{sema_err_division_zero}}
}

#test
{
    let a = 10
    a = 20 // swc-expected-error {{sema_err_assign_to_let}}
}

#test
{
    const a = 10
    a = 20 // swc-expected-error {{sema_err_assign_to_const}}
}

#test
{
    const A: [4] s32 = [1's32, 2, 3, 4]
    A[0] = 0 // swc-expected-error {{sema_err_assign_not_lvalue}}
}

#test
{
    var ptr: [*] s32
    ptr += 1
    var ptr1: const [*] s32
    ptr1 += 1
}

enum R { A, B }
#test
{
    var a: R
    a = .A
}