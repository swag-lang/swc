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