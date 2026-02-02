#global internal

#test
{
    var a, b: s32
    a = b / 0 // swc-expected-error {{sema_err_division_zero}}
}

#test
{
    var a, b: s32
    a = b % 0 // swc-expected-error {{sema_err_division_zero}}
}