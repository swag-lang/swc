#global private

struct RestrictedCommutativeBox
{
    value: s32
}

impl RestrictedCommutativeBox
{
    #[Swag.Commutative(.Mul)]
    mtd(op: Swag.Operator) const opBinary(scalar: s32)->RestrictedCommutativeBox
        where op == .Mul or op == .Sub
    {
        #static switch op
        {
        case .Mul:
            return {value: .value * scalar}

        case .Sub:
            return {value: .value - scalar}

        }
    }
}

#test
{
    var box    = RestrictedCommutativeBox{value: 3}
    let result = 10 - box     // swc-expected-error {{sema_err_binary_operand_type}}
}
