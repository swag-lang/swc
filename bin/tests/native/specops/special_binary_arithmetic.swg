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
    mtd(op: string)  opBinary(other: const &GenBinaryPair'T)->GenBinaryPair'T
    {
        #if op == "+" do
            return {x: .x + other.x, y: .y + other.y}
        #elif op == "-" do
            return {x: .x - other.x, y: .y - other.y}
        #elif op == "*" do
            return {x: .x * other.x, y: .y * other.y}
        #elif op == "/" do
            return {x: .x / other.x, y: .y / other.y}
        #elif op == "%" do
            return {x: .x % other.x, y: .y % other.y}
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
