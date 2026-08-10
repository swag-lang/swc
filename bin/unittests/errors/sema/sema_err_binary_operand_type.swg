#global private

struct WhereRestrictedOperator
{
    value: s32
}

impl WhereRestrictedOperator
{
    mtd(op: Swag.Operator) const opBinary(other: WhereRestrictedOperator)->WhereRestrictedOperator
        where op == .Add
    {
        return {.value + other.value}
    }
}

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

#test
{
    let left   = WhereRestrictedOperator{1}
    let right  = WhereRestrictedOperator{2}
    let result = left - right     // swc-expected-error {{sema_err_binary_operand_type}}
}
