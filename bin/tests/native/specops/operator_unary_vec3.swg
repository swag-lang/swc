#global fileprivate

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
    func(op: string) opUnary(const me)->IntUnaryVec3'T
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

// Test: IntUnaryVec3's64 unary - with mixed positive/negative/zero
#test
{
    var value: IntUnaryVec3's64 = {x: 1000, y: 0, z: -1000}
    let neg = -value

    @assert(neg.x == -1000)
    @assert(neg.y == 0)
    @assert(neg.z == 1000)
}
