#global fileprivate

// ============================================================================
// Generic single-value box with +, -, ~ unary ops
// ============================================================================

struct(T) IntUnaryBox
{
    value: T
}

impl IntUnaryBox
{
    func(op: string) opUnary(const me)->IntUnaryBox'T
    {
        #if op == "+" do
            return {value: +me.value}
        #elif op == "-" do
            return {value: -me.value}
        #elif op == "~" do
            return {value: ~.value}
        #else do
            #error("unsupported unary operation [[" ++ op ++ "]]")
    }
}

// Test: unary + on IntUnaryBox'u32
#test
{
    var value: IntUnaryBox'u32 = {value: 42}
    let pos = +value

    @assert(pos.value == 42)
}

// Test: unary - and ~ on IntUnaryBox's32
#test
{
    var value: IntUnaryBox's32 = {value: 42}
    let neg = -value
    let inv = ~value

    @assert(neg.value == -42)
    @assert(inv.value == -43)
}

// Test: unary - on IntUnaryBox's32 with zero
#test
{
    var value: IntUnaryBox's32 = {value: 0}
    let neg = -value

    @assert(neg.value == 0)
}

// Test: unary ~ on IntUnaryBox'u32 with zero (all bits set)
#test
{
    var value: IntUnaryBox'u32 = {value: 0}
    let inv = ~value

    @assert(inv.value == 0xFFFF_FFFF)
}

// Test: unary ~ on IntUnaryBox'u8
#test
{
    var value: IntUnaryBox'u8 = {value: 0}
    let inv = ~value

    @assert(inv.value == 0xFF)
}

// Test: unary ~ on IntUnaryBox'u64 with zero
#test
{
    var value: IntUnaryBox'u64 = {value: 0}
    let inv = ~value

    @assert(inv.value == 0xFFFF_FFFF_FFFF_FFFF)
}

// Test: unary + on IntUnaryBox's64 (identity for negative)
#test
{
    var value: IntUnaryBox's64 = {value: -100}
    let pos = +value

    @assert(pos.value == -100)
}

// Test: unary - on IntUnaryBox's64 with large negative
#test
{
    var value: IntUnaryBox's64 = {value: -999}
    let neg = -value

    @assert(neg.value == 999)
}

// Test: unary - on IntUnaryBox's16
#test
{
    var value: IntUnaryBox's16 = {value: 123}
    let neg = -value

    #assert(#typeof(neg) == IntUnaryBox's16)
    @assert(neg.value == -123)
}

// Test: unary ~ on IntUnaryBox'u16
#test
{
    var value: IntUnaryBox'u16 = {value: 0x00FF}
    let inv = ~value

    #assert(#typeof(inv) == IntUnaryBox'u16)
    @assert(inv.value == 0xFF00)
}

// Test: unary + on IntUnaryBox'u8
#test
{
    var value: IntUnaryBox'u8 = {value: 255}
    let pos = +value

    #assert(#typeof(pos) == IntUnaryBox'u8)
    @assert(pos.value == 255)
}

// Test: unary - on IntUnaryBox's8
#test
{
    var value: IntUnaryBox's8 = {value: 127}
    let neg = -value

    #assert(#typeof(neg) == IntUnaryBox's8)
    @assert(neg.value == -127)
}

// Test: double negation on IntUnaryBox's32
#test
{
    var value: IntUnaryBox's32 = {value: 42}
    let double_neg = -(-value)

    @assert(double_neg.value == 42)
}

// Test: double bitwise NOT on IntUnaryBox'u32 (identity)
#test
{
    var value: IntUnaryBox'u32 = {value: 0xDEAD_BEEF}
    let double_inv = ~(~value)

    @assert(double_inv.value == 0xDEAD_BEEF)
}

// Test: unary ~ on IntUnaryBox'u16 with 0xAAAA pattern
#test
{
    var value: IntUnaryBox'u16 = {value: 0xAAAA}
    let inv = ~value

    @assert(inv.value == 0x5555)
}
