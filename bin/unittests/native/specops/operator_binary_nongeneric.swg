#global private

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
    #[Swag.NoInline]
    mtd(op: Swag.Operator) const opBinary(other: RuntimeBinaryBox)->RuntimeBinaryBox
    {
        return {a: .a + other.a, b: .b + other.b, c: .c + other.c, d: .d + other.d}
    }

    #[Swag.NoInline]
    mtd(op: Swag.Operator) const opBinary(value: u64)->RuntimeBinaryBox
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

    Swag.require(sum.a == 11_u64)
    Swag.require(sum.b == 22_u64)
    Swag.require(sum.c == 33_u64)
    Swag.require(sum.d == 44_u64)
}

// Test: struct << scalar
#test
{
    var value   = RuntimeBinaryBox{a: 2, b: 3, c: 4, d: 5}
    let shifted = value << 2_u64

    Swag.require(shifted.a == 8_u64)
    Swag.require(shifted.b == 12_u64)
    Swag.require(shifted.c == 16_u64)
    Swag.require(shifted.d == 20_u64)
}

// Test: struct + struct with zeros
#test
{
    var lhs = RuntimeBinaryBox{a: 0, b: 0, c: 0, d: 0}
    var rhs = RuntimeBinaryBox{a: 100, b: 200, c: 300, d: 400}
    let sum = lhs + rhs

    Swag.require(sum.a == 100_u64)
    Swag.require(sum.b == 200_u64)
    Swag.require(sum.c == 300_u64)
    Swag.require(sum.d == 400_u64)
}

// Test: struct << 0 (identity)
#test
{
    var value   = RuntimeBinaryBox{a: 7, b: 13, c: 42, d: 99}
    let shifted = value << 0_u64

    Swag.require(shifted.a == 7_u64)
    Swag.require(shifted.b == 13_u64)
    Swag.require(shifted.c == 42_u64)
    Swag.require(shifted.d == 99_u64)
}

// Test: chaining struct + struct + struct
#test
{
    var a   = RuntimeBinaryBox{a: 1, b: 1, c: 1, d: 1}
    var b   = RuntimeBinaryBox{a: 2, b: 2, c: 2, d: 2}
    var c   = RuntimeBinaryBox{a: 3, b: 3, c: 3, d: 3}
    let sum = a + b + c

    Swag.require(sum.a == 6_u64)
    Swag.require(sum.b == 6_u64)
    Swag.require(sum.c == 6_u64)
    Swag.require(sum.d == 6_u64)
}
