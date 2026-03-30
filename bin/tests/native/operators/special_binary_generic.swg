#global fileprivate
#global skip

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

// ============================================================================
// Generic struct(T) with func(op: string) opBinary -- arithmetic ops
// ============================================================================

struct(T) GenBinaryPair
{
    x: T
    y: T
}

impl GenBinaryPair
{
    #[Swag.Overload]
    func(op: string) opBinary(me, other: GenBinaryPair'T)->GenBinaryPair'T
    {
        #if op == "+" do
            return {x: me.x + other.x, y: me.y + other.y}
        #elif op == "-" do
            return {x: me.x - other.x, y: me.y - other.y}
        #elif op == "*" do
            return {x: me.x * other.x, y: me.y * other.y}
        #elif op == "/" do
            return {x: me.x / other.x, y: me.y / other.y}
        #elif op == "%" do
            return {x: me.x % other.x, y: me.y % other.y}
        #else do
            #error("unsupported binary operation [[" ++ op ++ "]]")
    }

    #[Swag.Overload]
    func(op: string) opBinary(me, scalar: T)->GenBinaryPair'T
    {
        #if op == "+" do
            return {x: me.x + scalar, y: me.y + scalar}
        #elif op == "-" do
            return {x: me.x - scalar, y: me.y - scalar}
        #elif op == "*" do
            return {x: me.x * scalar, y: me.y * scalar}
        #elif op == "/" do
            return {x: me.x / scalar, y: me.y / scalar}
        #elif op == "%" do
            return {x: me.x % scalar, y: me.y % scalar}
        #else do
            #error("unsupported binary operation [[" ++ op ++ "]]")
    }
}

// Test: generic pair + pair with u32
#test
{
    var a: GenBinaryPair'u32 = {x: 10, y: 20}
    var b: GenBinaryPair'u32 = {x: 3, y: 7}
    let sum = a + b

    #assert(#typeof(sum) == GenBinaryPair'u32)
    @assert(sum.x == 13)
    @assert(sum.y == 27)
}

// Test: generic pair - pair with s32
#test
{
    var a: GenBinaryPair's32 = {x: 10, y: 20}
    var b: GenBinaryPair's32 = {x: 3, y: 7}
    let diff = a - b

    @assert(diff.x == 7)
    @assert(diff.y == 13)
}

// Test: generic pair - pair with negative result (s32)
#test
{
    var a: GenBinaryPair's32 = {x: 3, y: 7}
    var b: GenBinaryPair's32 = {x: 10, y: 20}
    let diff = a - b

    @assert(diff.x == -7)
    @assert(diff.y == -13)
}

// Test: generic pair * pair with u64
#test
{
    var a: GenBinaryPair'u64 = {x: 5, y: 6}
    var b: GenBinaryPair'u64 = {x: 3, y: 4}
    let prod = a * b

    @assert(prod.x == 15'u64)
    @assert(prod.y == 24'u64)
}

// Test: generic pair / pair with u32
#test
{
    var a: GenBinaryPair'u32 = {x: 20, y: 100}
    var b: GenBinaryPair'u32 = {x: 4, y: 10}
    let quot = a / b

    @assert(quot.x == 5)
    @assert(quot.y == 10)
}

// Test: generic pair % pair with u32
#test
{
    var a: GenBinaryPair'u32 = {x: 17, y: 25}
    var b: GenBinaryPair'u32 = {x: 5, y: 7}
    let rem = a % b

    @assert(rem.x == 2)
    @assert(rem.y == 4)
}

// Test: generic pair + scalar with s64
#test
{
    var a: GenBinaryPair's64 = {x: 10, y: -20}
    let result = a + 5's64

    @assert(result.x == 15)
    @assert(result.y == -15)
}

// Test: generic pair * scalar with u32
#test
{
    var a: GenBinaryPair'u32 = {x: 3, y: 7}
    let result = a * 10'u32

    @assert(result.x == 30)
    @assert(result.y == 70)
}

// Test: generic pair / scalar with u64
#test
{
    var a: GenBinaryPair'u64 = {x: 100, y: 200}
    let result = a / 10'u64

    @assert(result.x == 10'u64)
    @assert(result.y == 20'u64)
}

// Test: generic pair - scalar with s32
#test
{
    var a: GenBinaryPair's32 = {x: 5, y: 3}
    let result = a - 10's32

    @assert(result.x == -5)
    @assert(result.y == -7)
}

// Test: generic pair % scalar with u32
#test
{
    var a: GenBinaryPair'u32 = {x: 10, y: 17}
    let result = a % 3'u32

    @assert(result.x == 1)
    @assert(result.y == 2)
}

// Test: chaining generic pair arithmetic
#test
{
    var a: GenBinaryPair's32 = {x: 2, y: 3}
    var b: GenBinaryPair's32 = {x: 4, y: 5}
    var c: GenBinaryPair's32 = {x: 1, y: 1}
    let result = a + b - c

    @assert(result.x == 5)
    @assert(result.y == 7)
}

// Test: generic pair with u8 type
#test
{
    var a: GenBinaryPair'u8 = {x: 10, y: 20}
    var b: GenBinaryPair'u8 = {x: 3, y: 5}
    let sum = a + b

    #assert(#typeof(sum) == GenBinaryPair'u8)
    @assert(sum.x == 13)
    @assert(sum.y == 25)
}

// Test: generic pair with s16 type
#test
{
    var a: GenBinaryPair's16 = {x: 100, y: -200}
    var b: GenBinaryPair's16 = {x: 50, y: 300}
    let sum = a + b

    #assert(#typeof(sum) == GenBinaryPair's16)
    @assert(sum.x == 150)
    @assert(sum.y == 100)
}

// ============================================================================
// Generic struct(T) with bitwise ops
// ============================================================================

struct(T) GenBitwisePair
{
    x: T
    y: T
}

impl GenBitwisePair
{
    func(op: string) opBinary(me, other: GenBitwisePair'T)->GenBitwisePair'T
    {
        #if op == "&" do
            return {x: me.x & other.x, y: me.y & other.y}
        #elif op == "|" do
            return {x: me.x | other.x, y: me.y | other.y}
        #elif op == "^" do
            return {x: me.x ^ other.x, y: me.y ^ other.y}
        #elif op == "<<" do
            return {x: me.x << other.x, y: me.y << other.y}
        #elif op == ">>" do
            return {x: me.x >> other.x, y: me.y >> other.y}
        #else do
            #error("unsupported bitwise operation [[" ++ op ++ "]]")
    }
}

// Test: bitwise AND with u32
#test
{
    var a: GenBitwisePair'u32 = {x: 0xFF, y: 0x0F}
    var b: GenBitwisePair'u32 = {x: 0x0F, y: 0xFF}
    let result = a & b

    @assert(result.x == 0x0F)
    @assert(result.y == 0x0F)
}

// Test: bitwise OR with u32
#test
{
    var a: GenBitwisePair'u32 = {x: 0xF0, y: 0x0F}
    var b: GenBitwisePair'u32 = {x: 0x0F, y: 0xF0}
    let result = a | b

    @assert(result.x == 0xFF)
    @assert(result.y == 0xFF)
}

// Test: bitwise XOR with u64
#test
{
    var a: GenBitwisePair'u64 = {x: 0xFF00, y: 0x00FF}
    var b: GenBitwisePair'u64 = {x: 0xFFFF, y: 0xFFFF}
    let result = a ^ b

    @assert(result.x == 0x00FF'u64)
    @assert(result.y == 0xFF00'u64)
}

// Test: bitwise shift left with u32
#test
{
    var a: GenBitwisePair'u32 = {x: 1, y: 3}
    var b: GenBitwisePair'u32 = {x: 4, y: 2}
    let result = a << b

    @assert(result.x == 16)
    @assert(result.y == 12)
}

// Test: bitwise shift right with u32
#test
{
    var a: GenBitwisePair'u32 = {x: 256, y: 64}
    var b: GenBitwisePair'u32 = {x: 4, y: 3}
    let result = a >> b

    @assert(result.x == 16)
    @assert(result.y == 8)
}

// Test: bitwise AND with u8
#test
{
    var a: GenBitwisePair'u8 = {x: 0b1010_1010, y: 0b1100_1100}
    var b: GenBitwisePair'u8 = {x: 0b1111_0000, y: 0b0000_1111}
    let result = a & b

    @assert(result.x == 0b1010_0000)
    @assert(result.y == 0b0000_1100)
}

// Test: bitwise XOR self gives zero
#test
{
    var a: GenBitwisePair'u32 = {x: 12345, y: 67890}
    let result = a ^ a

    @assert(result.x == 0)
    @assert(result.y == 0)
}

// Test: bitwise OR with zero (identity)
#test
{
    var a: GenBitwisePair'u64 = {x: 0xDEAD_BEEF, y: 0xCAFE_BABE}
    var zero: GenBitwisePair'u64 = {x: 0, y: 0}
    let result = a | zero

    @assert(result.x == 0xDEAD_BEEF'u64)
    @assert(result.y == 0xCAFE_BABE'u64)
}

// ============================================================================
// Generic Vec3 with arithmetic + scalar overload
// ============================================================================

struct(T) GenVec3
{
    x: T
    y: T
    z: T
}

impl GenVec3
{
    #[Swag.Overload]
    func(op: string) opBinary(me, other: GenVec3'T)->GenVec3'T
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

    #[Swag.Overload]
    func(op: string) opBinary(me, scalar: T)->GenVec3'T
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
}

// Test: GenVec3 + GenVec3 with s32
#test
{
    var a: GenVec3's32 = {x: 1, y: 2, z: 3}
    var b: GenVec3's32 = {x: 10, y: 20, z: 30}
    let sum = a + b

    #assert(#typeof(sum) == GenVec3's32)
    @assert(sum.x == 11)
    @assert(sum.y == 22)
    @assert(sum.z == 33)
}

// Test: GenVec3 - GenVec3 with s64
#test
{
    var a: GenVec3's64 = {x: 100, y: 200, z: 300}
    var b: GenVec3's64 = {x: 150, y: 50, z: 300}
    let diff = a - b

    @assert(diff.x == -50)
    @assert(diff.y == 150)
    @assert(diff.z == 0)
}

// Test: GenVec3 * GenVec3 component-wise with u32
#test
{
    var a: GenVec3'u32 = {x: 2, y: 3, z: 4}
    var b: GenVec3'u32 = {x: 5, y: 6, z: 7}
    let prod = a * b

    @assert(prod.x == 10)
    @assert(prod.y == 18)
    @assert(prod.z == 28)
}

// Test: GenVec3 / GenVec3 with u64
#test
{
    var a: GenVec3'u64 = {x: 100, y: 200, z: 300}
    var b: GenVec3'u64 = {x: 10, y: 20, z: 30}
    let quot = a / b

    @assert(quot.x == 10'u64)
    @assert(quot.y == 10'u64)
    @assert(quot.z == 10'u64)
}

// Test: GenVec3 * scalar with u32
#test
{
    var a: GenVec3'u32 = {x: 1, y: 2, z: 3}
    let result = a * 10'u32

    @assert(result.x == 10)
    @assert(result.y == 20)
    @assert(result.z == 30)
}

// Test: GenVec3 + scalar with s32
#test
{
    var a: GenVec3's32 = {x: -5, y: 0, z: 5}
    let result = a + 10's32

    @assert(result.x == 5)
    @assert(result.y == 10)
    @assert(result.z == 15)
}

// Test: GenVec3 / scalar with u64
#test
{
    var a: GenVec3'u64 = {x: 100, y: 200, z: 300}
    let result = a / 10'u64

    @assert(result.x == 10'u64)
    @assert(result.y == 20'u64)
    @assert(result.z == 30'u64)
}

// Test: chaining GenVec3 operations
#test
{
    var a: GenVec3's32 = {x: 1, y: 2, z: 3}
    var b: GenVec3's32 = {x: 4, y: 5, z: 6}
    var c: GenVec3's32 = {x: 10, y: 10, z: 10}
    let result = a + b - c

    @assert(result.x == -5)
    @assert(result.y == -3)
    @assert(result.z == -1)
}

// Test: GenVec3 with u8
#test
{
    var a: GenVec3'u8 = {x: 10, y: 20, z: 30}
    var b: GenVec3'u8 = {x: 1, y: 2, z: 3}
    let sum = a + b
    let diff = a - b

    #assert(#typeof(sum) == GenVec3'u8)
    @assert(sum.x == 11)
    @assert(sum.y == 22)
    @assert(sum.z == 33)
    @assert(diff.x == 9)
    @assert(diff.y == 18)
    @assert(diff.z == 27)
}

// Test: GenVec3 - scalar with s64
#test
{
    var a: GenVec3's64 = {x: 0, y: 0, z: 0}
    let result = a - 42's64

    @assert(result.x == -42)
    @assert(result.y == -42)
    @assert(result.z == -42)
}
