#global fileprivate // swc-option suite-test

#test
{
    var a, b: s32
    a = b / 0 // swc-expected-error {{safety_err_division_zero}}
}

#test
{
    var a, b: s32
    a = b % 0 // swc-expected-error {{safety_err_division_zero}}
}

#test
{
    var a, b: s32
    a = b / (1 - 1) // swc-expected-error {{safety_err_division_zero}}
}

#test
{
    var a, b: s32
    a = b % (2 - 2) // swc-expected-error {{safety_err_division_zero}}
}

#test
{
    var a: s32
    var b: bool = true
    a = a + b // swc-expected-error {{sema_err_binary_operand_type}}
}
