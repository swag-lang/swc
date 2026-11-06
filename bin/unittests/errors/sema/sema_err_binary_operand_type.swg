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
        return WhereRestrictedOperator{.value + other.value}
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
    let bytePtr = cast([*] u8, &bytes[0])
    let wordPtr = cast([*] u32, &bytes[4])

    let a = wordPtr - bytePtr     // swc-expected-error {{sema_err_binary_operand_type}}
}

#test
{
    var bytes: [8] u8
    let bytePtr = cast([*] u8, &bytes[0])
    let wordPtr = cast([*] u32, &bytes[4])

    let b = bytePtr - wordPtr     // swc-expected-error {{sema_err_binary_operand_type}}
}

#test
{
    let left   = WhereRestrictedOperator{1}
    let right  = WhereRestrictedOperator{2}
    let result = left - right     // swc-expected-error {{sema_err_binary_operand_type}}
}

// A compound operator overloaded for a value, given a pointer: the operator does not apply to the
// pair, and the pointer beside a struct is not read as pointer arithmetic.
struct PointerAccumulator
{
    total: s32
}

impl PointerAccumulator
{
    mtd(op: Swag.Operator) opAssign(value: s32)
    {
        .total += value
    }
}

#test
{
    var acc:   PointerAccumulator
    var other: PointerAccumulator
    acc += &other     // swc-expected-error {{sema_err_binary_operand_type}}
}

#test
{
    var acc:    PointerAccumulator
    var number: s32
    acc += &number     // swc-expected-error {{sema_err_binary_operand_type}}
}
