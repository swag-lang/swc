#global fileprivate

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
    func(op: string) opBinary(const me, other: const &GenBinaryPair'T)->GenBinaryPair'T
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
    func(op: string) opBinary(const me, scalar: T)->GenBinaryPair'T
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
    func(op: string) opBinary(const me, other: const &GenBitwisePair'T)->GenBitwisePair'T
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
    func(op: string) opBinary(const me, other: const &GenVec3'T)->GenVec3'T
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
    func(op: string) opBinary(const me, scalar: T)->GenVec3'T
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
