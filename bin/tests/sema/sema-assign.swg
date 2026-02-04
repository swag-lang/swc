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

#test
{
    var a: f32
    a += 1's16
}

#test
{
    var a: f32
    a = 1
}

#test
{
    var p: [*] s32
    var i: s32
    p += i
    p = p + i
    p = i + p
    p -= 1
    var d: s64
    d = p - p
}

#test
{
    var a: s32
    a = 1.5 // swc-expected-error {{sema_err_cannot_cast}}
}

#test
{
    var a: s32
    a += 1.5 // swc-expected-error {{sema_err_cannot_cast}}
}

#test
{
    var a: f32
    a &= 1 // swc-expected-error {{sema_err_binary_operand_type}}
}

#test
{
    var p: [*] s32
    p += 1.0 // swc-expected-error {{sema_err_cannot_cast}}
}

struct Pair { a: s32; b: bool }

#test
{
    var a: s32
    var b: s32
    a, b = 1
}

#test
{
    var s: Pair
    var a: s32
    var b: bool
    (a, b) = s
}

#test
{
    var s: Pair
    var a: s32
    (a, ?) = s
}

#test
{
    var a: s32
    var b: s32
    (a, b) = 1 // swc-expected-error {{sema_err_decomposition_not_struct}}
}

#test
{
    var s: Pair
    var a: s32
    var b: bool
    var c: s32
    (a, b, c) = s // swc-expected-error {{sema_err_decomposition_too_many_names}}
}

#test
{
    var s: Pair
    var a: s32
    (a) = s // swc-expected-error {{sema_err_decomposition_not_enough_names}}
}

#test
{
    var s: Pair
    var a: s32
    var b: s32
    (a, b) = s // swc-expected-error {{sema_err_cannot_cast}}
}
