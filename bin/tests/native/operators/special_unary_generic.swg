#global fileprivate
#global skip

// ============================================================================
// Generic single-value box with +, -, ~ unary ops
// ============================================================================

struct(T) IntUnaryBox
{
    value: T
}

impl IntUnaryBox
{
    func(op: string) opUnary(me)->IntUnaryBox'T
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

// ============================================================================
// Generic bool box with ! unary op
// ============================================================================

struct(T) BoolUnaryBox
{
    value: T
}

impl BoolUnaryBox
{
    func(op: string) opUnary(me)->BoolUnaryBox'T
    {
        #if op == "!" do
            return {value: !me.value}
        #else do
            #error("unsupported unary operation [[" ++ op ++ "]]")
    }
}

// ============================================================================
// Generic 3-component vector with +, -, ~ unary ops
// ============================================================================

struct(T) IntUnaryVec3
{
    x: T
    y: T
    z: T
}

impl IntUnaryVec3
{
    func(op: string) opUnary(me)->IntUnaryVec3'T
    {
        #if op == "+" do
            return {x: +me.x, y: +me.y, z: +me.z}
        #elif op == "-" do
            return {x: -me.x, y: -me.y, z: -me.z}
        #elif op == "~" do
            return {x: ~me.x, y: ~me.y, z: ~me.z}
        #else do
            #error("unsupported unary operation [[" ++ op ++ "]]")
    }
}

// --- Original tests ---

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

// Test: unary ! on BoolUnaryBox'bool (false -> true)
#test
{
    var value: BoolUnaryBox'bool = {value: false}
    let flipped = !value

    @assert(flipped.value)
}

// Test: unary + on IntUnaryVec3'u64
#test
{
    var value: IntUnaryVec3'u64 = {x: 1, y: 2, z: 3}
    let pos = +value

    @assert(pos.x == 1)
    @assert(pos.y == 2)
    @assert(pos.z == 3)
}

// Test: unary - and ~ on IntUnaryVec3's64
#test
{
    var value: IntUnaryVec3's64 = {x: 1, y: -2, z: 3}
    let neg = -value
    let inv = ~value

    @assert(neg.x == -1)
    @assert(neg.y == 2)
    @assert(neg.z == -3)
    @assert(inv.x == -2)
    @assert(inv.y == 1)
    @assert(inv.z == -4)
}

// --- New tests ---

// Test: unary ! on BoolUnaryBox'bool (true -> false)
#test
{
    var value: BoolUnaryBox'bool = {value: true}
    let flipped = !value

    @assert(!flipped.value)
}

// Test: double negation on BoolUnaryBox'bool
#test
{
    var value: BoolUnaryBox'bool = {value: true}
    let double_flip = !(!value)

    @assert(double_flip.value)
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

// Test: IntUnaryVec3's32 with all zeros
#test
{
    var value: IntUnaryVec3's32 = {x: 0, y: 0, z: 0}
    let neg = -value
    let inv = ~value

    @assert(neg.x == 0)
    @assert(neg.y == 0)
    @assert(neg.z == 0)
    @assert(inv.x == -1)
    @assert(inv.y == -1)
    @assert(inv.z == -1)
}

// Test: IntUnaryVec3'u32 with unary +
#test
{
    var value: IntUnaryVec3'u32 = {x: 100, y: 200, z: 300}
    let pos = +value

    #assert(#typeof(pos) == IntUnaryVec3'u32)
    @assert(pos.x == 100)
    @assert(pos.y == 200)
    @assert(pos.z == 300)
}

// Test: IntUnaryVec3'u32 bitwise NOT
#test
{
    var value: IntUnaryVec3'u32 = {x: 0, y: 0xFFFF_FFFF, z: 0x0000_00FF}
    let inv = ~value

    @assert(inv.x == 0xFFFF_FFFF)
    @assert(inv.y == 0)
    @assert(inv.z == 0xFFFF_FF00)
}

// Test: IntUnaryVec3's16
#test
{
    var value: IntUnaryVec3's16 = {x: 10, y: -20, z: 30}
    let neg = -value

    #assert(#typeof(neg) == IntUnaryVec3's16)
    @assert(neg.x == -10)
    @assert(neg.y == 20)
    @assert(neg.z == -30)
}

// Test: IntUnaryVec3'u8 bitwise NOT
#test
{
    var value: IntUnaryVec3'u8 = {x: 0x0F, y: 0xF0, z: 0xAA}
    let inv = ~value

    #assert(#typeof(inv) == IntUnaryVec3'u8)
    @assert(inv.x == 0xF0)
    @assert(inv.y == 0x0F)
    @assert(inv.z == 0x55)
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

// Test: double negation on IntUnaryVec3's32
#test
{
    var value: IntUnaryVec3's32 = {x: 1, y: -2, z: 3}
    let double_neg = -(-value)

    @assert(double_neg.x == 1)
    @assert(double_neg.y == -2)
    @assert(double_neg.z == 3)
}

// Test: double bitwise NOT on IntUnaryVec3'u64 (identity)
#test
{
    var value: IntUnaryVec3'u64 = {x: 0xCAFE, y: 0xBABE, z: 0xDEAD}
    let double_inv = ~(~value)

    @assert(double_inv.x == 0xCAFE'u64)
    @assert(double_inv.y == 0xBABE'u64)
    @assert(double_inv.z == 0xDEAD'u64)
}

// Test: unary ~ on IntUnaryBox'u16 with 0xAAAA pattern
#test
{
    var value: IntUnaryBox'u16 = {value: 0xAAAA}
    let inv = ~value

    @assert(inv.value == 0x5555)
}

// Test: IntUnaryVec3's64 unary - with mixed positive/negative/zero
#test
{
    var value: IntUnaryVec3's64 = {x: 1000, y: 0, z: -1000}
    let neg = -value

    @assert(neg.x == -1000)
    @assert(neg.y == 0)
    @assert(neg.z == 1000)
}
