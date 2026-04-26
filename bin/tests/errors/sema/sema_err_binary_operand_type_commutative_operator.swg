#global fileprivate

struct RestrictedCommutativeBox
{
    value: s32
}

impl RestrictedCommutativeBox
{
    #[Swag.Commutative("*")]
    mtd(op: string) const opBinary(scalar: s32)->RestrictedCommutativeBox
    {
        #if op == "*" do
            return {value: .value * scalar}
        #elif op == "-" do
            return {value: .value - scalar}
        #else do
            #error("unsupported binary operation [[" ++ op ++ "]]")
    }
}

#test
{
    var box = RestrictedCommutativeBox{value: 3}
    let result = 10 - box // swc-expected-error {{sema_err_binary_operand_type}}
}
