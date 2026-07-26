#global private

struct RestrictedCommutativeBox
{
    value: s32
}

impl RestrictedCommutativeBox
{
    #[Swag.Commutative(.Mul)]
    mtd(op: Swag.Operator) const opBinary(scalar: s32)->RestrictedCommutativeBox
    {
        #static if op == .Mul do
            return {value: .value * scalar}
        elif op == .Sub do
            return {value: .value - scalar}
        else do
            #error("unsupported binary operation [[" ++ op.symbol() ++ "]]")
    }
}

#test
{
    var box    = RestrictedCommutativeBox{value: 3}
    let result = 10 - box     // swc-expected-error {{sema_err_binary_operand_type}}
}
