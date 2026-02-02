#global internal

#test
{
    var a, b: s32
    a = b
    a += b
    var c: s32
    a = c / 0 // swc-expected-error {{sema_err_division_zero}}
}