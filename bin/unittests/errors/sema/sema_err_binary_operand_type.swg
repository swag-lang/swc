#global private

#test
{
    var a: s32
    var b: bool = true
    a = a + b     // swc-expected-error {{sema_err_binary_operand_type}}
}

#test
{
    var bytes: [8] u8
    let bytePtr = cast([*] u8) &bytes[0]
    let wordPtr = cast([*] u32) &bytes[4]

    let a = wordPtr - bytePtr     // swc-expected-error {{sema_err_binary_operand_type}}
}

#test
{
    var bytes: [8] u8
    let bytePtr = cast([*] u8) &bytes[0]
    let wordPtr = cast([*] u32) &bytes[4]

    let b = bytePtr - wordPtr     // swc-expected-error {{sema_err_binary_operand_type}}
}
