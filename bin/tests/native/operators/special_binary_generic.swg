#global fileprivate

struct RuntimeBinaryBox
{
    a: u64
    b: u64
    c: u64
    d: u64
}

impl RuntimeBinaryBox
{
    #[Swag.Overload, Swag.NoInline]
    mtd const opBinary(other: const &RuntimeBinaryBox)->RuntimeBinaryBox
    {
        return {a: .a + other.a, b: .b + other.b, c: .c + other.c, d: .d + other.d}
    }

    #[Swag.Overload, Swag.NoInline]
    mtd const opBinary(value: u64)->RuntimeBinaryBox
    {
        return {a: .a << value, b: .b << value, c: .c << value, d: .d << value}
    }
}

#test
{
    var lhs = RuntimeBinaryBox{a: 1, b: 2, c: 3, d: 4}
    var rhs = RuntimeBinaryBox{a: 10, b: 20, c: 30, d: 40}
    let sum = lhs + rhs

    #assert(#typeof(sum) == RuntimeBinaryBox)

    @assert(sum.a == 11'u64)
    @assert(sum.b == 22'u64)
    @assert(sum.c == 33'u64)
    @assert(sum.d == 44'u64)
}

#test
{
    var value = RuntimeBinaryBox{a: 2, b: 3, c: 4, d: 5}
    let shifted = value << 2'u64

    @assert(shifted.a == 8'u64)
    @assert(shifted.b == 12'u64)
    @assert(shifted.c == 16'u64)
    @assert(shifted.d == 20'u64)
}
