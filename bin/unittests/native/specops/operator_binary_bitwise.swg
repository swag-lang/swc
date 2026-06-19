#global fileprivate

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
