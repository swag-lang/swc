#global fileprivate

// ============================================================================
// Non-generic struct with overloaded opBinary (original tests)
// ============================================================================

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
    mtd(op: string) const opBinary(other: const &RuntimeBinaryBox)->RuntimeBinaryBox
    {
        return {a: .a + other.a, b: .b + other.b, c: .c + other.c, d: .d + other.d}
    }

    #[Swag.Overload, Swag.NoInline]
    mtd(op: string) const opBinary(value: u64)->RuntimeBinaryBox
    {
        return {a: .a << value, b: .b << value, c: .c << value, d: .d << value}
    }
}

// Test: struct + struct
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

// Test: struct << scalar
#test
{
    var value = RuntimeBinaryBox{a: 2, b: 3, c: 4, d: 5}
    let shifted = value << 2'u64

    @assert(shifted.a == 8'u64)
    @assert(shifted.b == 12'u64)
    @assert(shifted.c == 16'u64)
    @assert(shifted.d == 20'u64)
}

// Test: struct + struct with zeros
#test
{
    var lhs = RuntimeBinaryBox{a: 0, b: 0, c: 0, d: 0}
    var rhs = RuntimeBinaryBox{a: 100, b: 200, c: 300, d: 400}
    let sum = lhs + rhs

    @assert(sum.a == 100'u64)
    @assert(sum.b == 200'u64)
    @assert(sum.c == 300'u64)
    @assert(sum.d == 400'u64)
}

// Test: struct << 0 (identity)
#test
{
    var value = RuntimeBinaryBox{a: 7, b: 13, c: 42, d: 99}
    let shifted = value << 0'u64

    @assert(shifted.a == 7'u64)
    @assert(shifted.b == 13'u64)
    @assert(shifted.c == 42'u64)
    @assert(shifted.d == 99'u64)
}

// Test: chaining struct + struct + struct
#test
{
    var a = RuntimeBinaryBox{a: 1, b: 1, c: 1, d: 1}
    var b = RuntimeBinaryBox{a: 2, b: 2, c: 2, d: 2}
    var c = RuntimeBinaryBox{a: 3, b: 3, c: 3, d: 3}
    let sum = a + b + c

    @assert(sum.a == 6'u64)
    @assert(sum.b == 6'u64)
    @assert(sum.c == 6'u64)
    @assert(sum.d == 6'u64)
}
