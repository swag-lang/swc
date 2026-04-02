#global fileprivate

// Real-life example: a generic 3D vector with overloaded unary and binary operators.

struct(T) Vector3
{
    x: T
    y: T
    z: T
}

impl Vector3
{
    // Unary operators: +, -, ~
    func(op: string) opUnary(const me)->Vector3'T
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

    // Binary operators: vector op vector
    #[Swag.Overload]
    func(op: string) opBinary(const me, other: const &Vector3'T)->Vector3'T
    {
        #if op == "+" do
            return {x: me.x + other.x, y: me.y + other.y, z: me.z + other.z}
        #elif op == "-" do
            return {x: me.x - other.x, y: me.y - other.y, z: me.z - other.z}
        #elif op == "*" do
            return {x: me.x * other.x, y: me.y * other.y, z: me.z * other.z}
        #elif op == "/" do
            return {x: me.x / other.x, y: me.y / other.y, z: me.z / other.z}
        #else do
            #error("unsupported binary operation [[" ++ op ++ "]]")
    }

    // Binary operators: vector op scalar
    #[Swag.Overload]
    func(op: string) opBinary(const me, scalar: T)->Vector3'T
    {
        #if op == "+" do
            return {x: me.x + scalar, y: me.y + scalar, z: me.z + scalar}
        #elif op == "-" do
            return {x: me.x - scalar, y: me.y - scalar, z: me.z - scalar}
        #elif op == "*" do
            return {x: me.x * scalar, y: me.y * scalar, z: me.z * scalar}
        #elif op == "/" do
            return {x: me.x / scalar, y: me.y / scalar, z: me.z / scalar}
        #else do
            #error("unsupported binary operation [[" ++ op ++ "]]")
    }

    // Dot product helper
    func dot(a: const &Vector3'T, b: const &Vector3'T)->T
    {
        return a.x * b.x + a.y * b.y + a.z * b.z
    }

    // Squared length helper
    func lengthSq(const me)->T
    {
        return me.x * me.x + me.y * me.y + me.z * me.z
    }
}

// ---------------------------------------------------------------------------
// Unary operator tests
// ---------------------------------------------------------------------------

// Test: unary + preserves values
#test
{
    var v: Vector3's32 = {x: 1, y: -2, z: 3}
    let pos = +v

    #assert(#typeof(pos) == Vector3's32)
    @assert(pos.x == 1)
    @assert(pos.y == -2)
    @assert(pos.z == 3)
}

// Test: unary - negates all components
#test
{
    var v: Vector3's32 = {x: 5, y: -10, z: 0}
    let neg = -v

    @assert(neg.x == -5)
    @assert(neg.y == 10)
    @assert(neg.z == 0)
}

// Test: unary ~ bitwise NOT
#test
{
    var v: Vector3'u32 = {x: 0, y: 0xFFFF_FFFF, z: 0x00FF_00FF}
    let inv = ~v

    @assert(inv.x == 0xFFFF_FFFF)
    @assert(inv.y == 0)
    @assert(inv.z == 0xFF00_FF00)
}

// Test: double negation is identity
#test
{
    var v: Vector3's64 = {x: 42, y: -99, z: 0}
    let dn = -(-v)

    @assert(dn.x == 42)
    @assert(dn.y == -99)
    @assert(dn.z == 0)
}

// Test: double bitwise NOT is identity
#test
{
    var v: Vector3'u64 = {x: 0xCAFE, y: 0xBABE, z: 0xDEAD}
    let di = ~(~v)

    @assert(di.x == 0xCAFE'u64)
    @assert(di.y == 0xBABE'u64)
    @assert(di.z == 0xDEAD'u64)
}

// ---------------------------------------------------------------------------
// Binary operator tests: vector op vector
// ---------------------------------------------------------------------------

// Test: vector + vector with s32
#test
{
    var a: Vector3's32 = {x: 1, y: 2, z: 3}
    var b: Vector3's32 = {x: 10, y: 20, z: 30}
    let sum = a + b

    #assert(#typeof(sum) == Vector3's32)
    @assert(sum.x == 11)
    @assert(sum.y == 22)
    @assert(sum.z == 33)
}

// Test: vector - vector with negative results
#test
{
    var a: Vector3's32 = {x: 3, y: 5, z: 1}
    var b: Vector3's32 = {x: 10, y: 5, z: 8}
    let diff = a - b

    @assert(diff.x == -7)
    @assert(diff.y == 0)
    @assert(diff.z == -7)
}

// Test: vector * vector component-wise
#test
{
    var a: Vector3'u32 = {x: 2, y: 3, z: 4}
    var b: Vector3'u32 = {x: 5, y: 6, z: 7}
    let prod = a * b

    @assert(prod.x == 10)
    @assert(prod.y == 18)
    @assert(prod.z == 28)
}

// Test: vector / vector
#test
{
    var a: Vector3'u64 = {x: 100, y: 200, z: 300}
    var b: Vector3'u64 = {x: 10, y: 20, z: 30}
    let quot = a / b

    @assert(quot.x == 10'u64)
    @assert(quot.y == 10'u64)
    @assert(quot.z == 10'u64)
}

// ---------------------------------------------------------------------------
// Binary operator tests: vector op scalar
// ---------------------------------------------------------------------------

// Test: vector * scalar (uniform scale)
#test
{
    var v: Vector3's32 = {x: 1, y: -2, z: 3}
    let scaled = v * 3's32

    @assert(scaled.x == 3)
    @assert(scaled.y == -6)
    @assert(scaled.z == 9)
}

// Test: vector + scalar (offset all components)
#test
{
    var v: Vector3's32 = {x: -5, y: 0, z: 5}
    let result = v + 10's32

    @assert(result.x == 5)
    @assert(result.y == 10)
    @assert(result.z == 15)
}

// Test: vector / scalar
#test
{
    var v: Vector3'u64 = {x: 100, y: 200, z: 300}
    let result = v / 10'u64

    @assert(result.x == 10'u64)
    @assert(result.y == 20'u64)
    @assert(result.z == 30'u64)
}

// Test: vector - scalar with underflow into negatives
#test
{
    var v: Vector3's32 = {x: 2, y: 5, z: 0}
    let result = v - 3's32

    @assert(result.x == -1)
    @assert(result.y == 2)
    @assert(result.z == -3)
}

// ---------------------------------------------------------------------------
// Chaining and combined operations
// ---------------------------------------------------------------------------

// Test: chaining binary ops
#test
{
    var a: Vector3's32 = {x: 1, y: 2, z: 3}
    var b: Vector3's32 = {x: 4, y: 5, z: 6}
    var c: Vector3's32 = {x: 10, y: 10, z: 10}
    let result = a + b - c

    @assert(result.x == -5)
    @assert(result.y == -3)
    @assert(result.z == -1)
}

// Test: negation then addition
#test
{
    var a: Vector3's32 = {x: 1, y: 2, z: 3}
    var b: Vector3's32 = {x: 1, y: 2, z: 3}
    let result = (-a) + b

    @assert(result.x == 0)
    @assert(result.y == 0)
    @assert(result.z == 0)
}

// Test: scale then subtract
#test
{
    var a: Vector3's32 = {x: 3, y: 6, z: 9}
    var b: Vector3's32 = {x: 1, y: 2, z: 3}
    let result = a - b * 2's32

    @assert(result.x == 1)
    @assert(result.y == 2)
    @assert(result.z == 3)
}

// ---------------------------------------------------------------------------
// Dot product and length
// ---------------------------------------------------------------------------

// Test: dot product of orthogonal vectors is zero
#test
{
    var a: Vector3's32 = {x: 1, y: 0, z: 0}
    var b: Vector3's32 = {x: 0, y: 1, z: 0}
    let d = Vector3's32.dot(&a, &b)

    @assert(d == 0)
}

// Test: dot product of parallel vectors
#test
{
    var a: Vector3's32 = {x: 2, y: 3, z: 4}
    var b: Vector3's32 = {x: 2, y: 3, z: 4}
    let d = Vector3's32.dot(&a, &b)

    // 4 + 9 + 16 = 29
    @assert(d == 29)
}

// Test: squared length
#test
{
    var v: Vector3's32 = {x: 3, y: 4, z: 0}
    let lsq = v.lengthSq()

    // 9 + 16 + 0 = 25
    @assert(lsq == 25)
}

// ---------------------------------------------------------------------------
// Multiple type instantiations
// ---------------------------------------------------------------------------

// Test: Vector3 with u8
#test
{
    var a: Vector3'u8 = {x: 10, y: 20, z: 30}
    var b: Vector3'u8 = {x: 1, y: 2, z: 3}
    let sum = a + b
    let diff = a - b

    #assert(#typeof(sum) == Vector3'u8)
    @assert(sum.x == 11)
    @assert(sum.y == 22)
    @assert(sum.z == 33)
    @assert(diff.x == 9)
    @assert(diff.y == 18)
    @assert(diff.z == 27)
}

// Test: Vector3 with s16
#test
{
    var v: Vector3's16 = {x: 100, y: -200, z: 300}
    let neg = -v

    #assert(#typeof(neg) == Vector3's16)
    @assert(neg.x == -100)
    @assert(neg.y == 200)
    @assert(neg.z == -300)
}

// Test: Vector3 with u64 scalar multiply
#test
{
    var v: Vector3'u64 = {x: 1, y: 2, z: 3}
    let result = v * 1000'u64

    @assert(result.x == 1000'u64)
    @assert(result.y == 2000'u64)
    @assert(result.z == 3000'u64)
}
