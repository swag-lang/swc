#global fileprivate

#test
{
    var a: s32
    var b: bool = true
    a = a + b // swc-expected-error {{sema_err_binary_operand_type}}
}
