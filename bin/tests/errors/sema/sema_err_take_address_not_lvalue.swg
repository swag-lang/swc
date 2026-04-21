#global fileprivate

#test
{
    var x = 0
    var y = &(x + 1) // swc-expected-error {{sema_err_take_address_not_lvalue}}
}

#test
{
    struct AA { x: s32 }
    var st: AA
    var z = &st.x
    var w = &(st.x + 1) // swc-expected-error {{sema_err_take_address_not_lvalue}}
}

#test
{
    var x: s32
    var p = &x
    var q = &(&x) // swc-expected-error {{sema_err_take_address_not_lvalue}}
}

#test
{
    var A = 10's32
    var PA = &A
    var PB = &(A + 1) // swc-expected-error {{sema_err_take_address_not_lvalue}}
}

#test
{
    var a: [4] s32
    var p = &(a[0] + 1) // swc-expected-error {{sema_err_take_address_not_lvalue}}
}

#test
{
    struct B { y: s32 }
    struct C { b: B }
    var c: C
    var q = &(c.b.y + 1) // swc-expected-error {{sema_err_take_address_not_lvalue}}
}

#test
{
    var x: s32
    var y = &(x + x) // swc-expected-error {{sema_err_take_address_not_lvalue}}
}

#test
{
    var a: [4] s32
    var i = 1's32
    var p = &(a[i] + 1) // swc-expected-error {{sema_err_take_address_not_lvalue}}
}
