#global fileprivate

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
    mtd(op: string) const opBinary(other: const &AmbiguousCommutativeRight)->AmbiguousCommutativeLeft
    {
        return {value: .value + other.value}
    }
}

impl AmbiguousCommutativeRight
{
    #[Swag.Commutative("+")]
    mtd(op: string) const opBinary(other: const &AmbiguousCommutativeLeft)->AmbiguousCommutativeRight
    {
        return {value: .value + other.value}
    }
}

#test
{
    var left = AmbiguousCommutativeLeft{value: 1}
    var right = AmbiguousCommutativeRight{value: 2}
    let result = left + right // swc-expected-error {{sema_err_ambiguous_symbol}}
}
