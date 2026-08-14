#global private

struct AmbiguousCommutativeLeft
{
    value: s32
}

struct AmbiguousCommutativeRight
{
    value: s32
}

impl AmbiguousCommutativeLeft
{
    mtd(op: Swag.Operator) const opBinary(other: AmbiguousCommutativeRight)->AmbiguousCommutativeLeft
    {
        return {value: .value + other.value}
    }
}

impl AmbiguousCommutativeRight
{
    #[Swag.Commutative(.Add)]
    mtd(op: Swag.Operator) const opBinary(other: AmbiguousCommutativeLeft)->AmbiguousCommutativeRight
    {
        return {value: .value + other.value}
    }
}

#test
{
    var left   = AmbiguousCommutativeLeft{value: 1}
    var right  = AmbiguousCommutativeRight{value: 2}
    let result = left + right     // swc-expected-error {{sema_err_ambiguous_symbol}}
}
