#global fileprivate

struct BinaryIntBox
{
    value: u32
}

impl BinaryIntBox
{
    #[Swag.Overload]
    mtd(op: string) const opBinary(other: const &BinaryIntBox)->BinaryIntBox
    {
        return {value: .value + other.value}
    }

    #[Swag.Overload]
    mtd(op: string) const opBinary(other: u32)->BinaryIntBox
    {
        return {value: .value << other}
    }
}

struct MissingConstMe
{
    value: u64
}

struct MutatingOtherRef
{
    value: u64
}

struct MutatingOtherPtr
{
    value: u64
}

struct(T) GenericMissingConstMe
{
    value: T
}

struct IndirectOtherByValue
{
    a: u64
    b: u64
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
