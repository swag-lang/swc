#global fileprivate

struct BinaryIntBox
{
    value: u32
}

impl BinaryIntBox
{
    mtd(op: string) const opBinary(other: const &BinaryIntBox)->BinaryIntBox
    {
        return {value: .value + other.value}
    }

    mtd(op: string) const opBinary(other: u32)->BinaryIntBox
    {
        return {value: .value << other}
    }
}

struct BinaryRightIntBox
{
    value: u32
}

impl BinaryRightIntBox
{
    #[Swag.Commutative]
    mtd(op: string) const opBinary(other: u32)->BinaryRightIntBox
    {
        #if op == "*" do
            return {value: .value * other}
        #else do
            #error("unsupported binary operation [[" ++ op ++ "]]")
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

#test
{
    var value = BinaryRightIntBox{value: 5}
    let scaled = 3'u32 * value

    #assert(#typeof(scaled) == BinaryRightIntBox)
    #assert(#typeof(scaled.value) == u32)
}
