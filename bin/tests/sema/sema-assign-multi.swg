#global internal

#test
{
    var a: s32
    var b: s32
    a, b = 1
    a, b += 1
}

#test
{
    var a: s32
    var b: s32
    a, b /= 0 // swc-expected-error {{sema_err_division_zero}}
}

#test
{
    var a: s32
    var b: s32
    a, ?, b = 1
}

#test
{
    var a: s32
    var b: s32
    a, b = 1.5 // swc-expected-error {{sema_err_cannot_cast}}
}

#test
{
    var a: s32
    var b: s32
    a, b += 1.5 // swc-expected-error {{sema_err_cannot_cast}}
}

#test
{
    var a: f32
    var b: f32
    a, b &= 1 // swc-expected-error {{sema_err_binary_operand_type}}
}

#test
{
    var a: f32
    var b: s32
    a, b = 1
}

#test
{
    var a: f32
    var b: bool
    a, b = 1
}
