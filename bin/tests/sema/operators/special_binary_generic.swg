#global fileprivate

struct BinaryIntBox
{
    value: u32
}

impl BinaryIntBox
{
    #[Swag.Overload]
    mtd const opBinary(other: const &BinaryIntBox)->BinaryIntBox
    {
        return {value: .value + other.value}
    }

    #[Swag.Overload]
    mtd const opBinary(other: u32)->BinaryIntBox
    {
        return {value: .value << other}
    }
}

#test
{
    var lhs  = BinaryIntBox{value: 40}
    var rhs  = BinaryIntBox{value: 2}
    let sum  = lhs + rhs

    #assert(#typeof(sum) == BinaryIntBox)
    #assert(#typeof(sum.value) == u32)
}

#test
{
    var value = BinaryIntBox{value: 2}
    let shift = value << 4'u32

    #assert(#typeof(shift) == BinaryIntBox)
    #assert(#typeof(shift.value) == u32)
}
