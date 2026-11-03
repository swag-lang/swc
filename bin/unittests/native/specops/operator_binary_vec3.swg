#global private

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
    func(op: Swag.Operator) opBinary(const me, other: GenVec3'T)->GenVec3'T
        where op == .Add or op == .Sub or op == .Mul or op == .Div
    {
        #static switch op
        {
        case .Add:
            return {x: me.x + other.x, y: me.y + other.y, z: me.z + other.z}

        case .Sub:
            return {x: me.x - other.x, y: me.y - other.y, z: me.z - other.z}

        case .Mul:
            return {x: me.x * other.x, y: me.y * other.y, z: me.z * other.z}

        case .Div:
            return {x: me.x / other.x, y: me.y / other.y, z: me.z / other.z}

        }
    }

    func(op: Swag.Operator) opBinary(const me, scalar: T)->GenVec3'T
        where op == .Add or op == .Sub or op == .Mul or op == .Div
    {
        #static switch op
        {
        case .Add:
            return {x: me.x + scalar, y: me.y + scalar, z: me.z + scalar}

        case .Sub:
            return {x: me.x - scalar, y: me.y - scalar, z: me.z - scalar}

        case .Mul:
            return {x: me.x * scalar, y: me.y * scalar, z: me.z * scalar}

        case .Div:
            return {x: me.x / scalar, y: me.y / scalar, z: me.z / scalar}

        }
    }
}

// Test: GenVec3 + GenVec3 with s32
#test
{
    var a: GenVec3's32 = {x: 1, y: 2, z: 3}
    var b: GenVec3's32 = {x: 10, y: 20, z: 30}
    let sum = a + b

    #assert(#typeof(sum) == GenVec3's32)
    Swag.require(sum.x == 11)
    Swag.require(sum.y == 22)
    Swag.require(sum.z == 33)
}

// Test: GenVec3 - GenVec3 with s64
#test
{
    var a: GenVec3's64 = {x: 100, y: 200, z: 300}
    var b: GenVec3's64 = {x: 150, y: 50, z: 300}
    let diff = a - b

    Swag.require(diff.x == -50)
    Swag.require(diff.y == 150)
    Swag.require(diff.z == 0)
}

// Test: GenVec3 * GenVec3 component-wise with u32
#test
{
    var a: GenVec3'u32 = {x: 2, y: 3, z: 4}
    var b: GenVec3'u32 = {x: 5, y: 6, z: 7}
    let prod = a * b

    Swag.require(prod.x == 10)
    Swag.require(prod.y == 18)
    Swag.require(prod.z == 28)
}

// Test: GenVec3 / GenVec3 with u64
#test
{
    var a: GenVec3'u64 = {x: 100, y: 200, z: 300}
    var b: GenVec3'u64 = {x: 10, y: 20, z: 30}
    let quot = a / b

    Swag.require(quot.x == 10'u64)
    Swag.require(quot.y == 10'u64)
    Swag.require(quot.z == 10'u64)
}

// Test: GenVec3 * scalar with u32
#test
{
    var a: GenVec3'u32 = {x: 1, y: 2, z: 3}
    let result         = a * 10'u32

    Swag.require(result.x == 10)
    Swag.require(result.y == 20)
    Swag.require(result.z == 30)
}

// Test: GenVec3 + scalar with s32
#test
{
    var a: GenVec3's32 = {x: -5, y: 0, z: 5}
    let result         = a + 10's32

    Swag.require(result.x == 5)
    Swag.require(result.y == 10)
    Swag.require(result.z == 15)
}

// Test: GenVec3 / scalar with u64
#test
{
    var a: GenVec3'u64 = {x: 100, y: 200, z: 300}
    let result         = a / 10'u64

    Swag.require(result.x == 10'u64)
    Swag.require(result.y == 20'u64)
    Swag.require(result.z == 30'u64)
}

// Test: chaining GenVec3 operations
#test
{
    var a: GenVec3's32 = {x: 1, y: 2, z: 3}
    var b: GenVec3's32 = {x: 4, y: 5, z: 6}
    var c: GenVec3's32 = {x: 10, y: 10, z: 10}
    let result         = a + b - c

    Swag.require(result.x == -5)
    Swag.require(result.y == -3)
    Swag.require(result.z == -1)
}

// Test: GenVec3 with u8
#test
{
    var a: GenVec3'u8 = {x: 10, y: 20, z: 30}
    var b: GenVec3'u8 = {x: 1, y: 2, z: 3}
    let sum           = a + b
    let diff          = a - b

    #assert(#typeof(sum) == GenVec3'u8)
    Swag.require(sum.x == 11)
    Swag.require(sum.y == 22)
    Swag.require(sum.z == 33)
    Swag.require(diff.x == 9)
    Swag.require(diff.y == 18)
    Swag.require(diff.z == 27)
}

// Test: GenVec3 - scalar with s64
#test
{
    var a: GenVec3's64 = {x: 0, y: 0, z: 0}
    let result         = a - 42's64

    Swag.require(result.x == -42)
    Swag.require(result.y == -42)
    Swag.require(result.z == -42)
}
