#global fileprivate

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
