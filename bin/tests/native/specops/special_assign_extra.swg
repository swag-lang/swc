#global fileprivate

// ============================================================================
// opAssign: subtraction and division operators
// ============================================================================

struct RuntimeArithAssignBox
{
    value: s32
    calls: s32
}

impl RuntimeArithAssignBox
{
    #[Swag.NoInline]
    mtd(op: string) opAssign(rhs: s32)
    {
        .calls += 1
        #if op == "+=" do
            .value += rhs
        #elif op == "-=" do
            .value -= rhs
        #elif op == "*=" do
            .value *= rhs
        #elif op == "/=" do
            .value /= rhs
        #elif op == "%=" do
            .value %= rhs
        #else do
            #error("unsupported opAssign op [[" ++ op ++ "]]")
    }
}

// Test: -=
#test
{
    var box = RuntimeArithAssignBox{value: 100}
    box -= 37

    @assert(box.value == 63)
    @assert(box.calls == 1)
}

// Test: /=
#test
{
    var box = RuntimeArithAssignBox{value: 100}
    box /= 4

    @assert(box.value == 25)
    @assert(box.calls == 1)
}

// Test: %=
#test
{
    var box = RuntimeArithAssignBox{value: 17}
    box %= 5

    @assert(box.value == 2)
    @assert(box.calls == 1)
}

// Test: sequential chained assigns
#test
{
    var box = RuntimeArithAssignBox{value: 10}
    box += 5
    box *= 3
    box -= 15

    @assert(box.value == 30)
    @assert(box.calls == 3)
}

// Test: -= to negative
#test
{
    var box = RuntimeArithAssignBox{value: 3}
    box -= 10

    @assert(box.value == -7)
    @assert(box.calls == 1)
}

// ============================================================================
// opAssign: bitwise operators
// ============================================================================

struct RuntimeBitAssignBox
{
    value: u32
    calls: s32
}

impl RuntimeBitAssignBox
{
    #[Swag.NoInline]
    mtd(op: string) opAssign(rhs: u32)
    {
        .calls += 1
        #if op == "&=" do
            .value &= rhs
        #elif op == "|=" do
            .value |= rhs
        #elif op == "^=" do
            .value ^= rhs
        #elif op == "<<=" do
            .value <<= rhs
        #elif op == ">>=" do
            .value >>= rhs
        #else do
            #error("unsupported opAssign op [[" ++ op ++ "]]")
    }
}

// Test: &=
#test
{
    var box = RuntimeBitAssignBox{value: 0xFF}
    box &= 0x0F

    @assert(box.value == 0x0F)
    @assert(box.calls == 1)
}

// Test: |=
#test
{
    var box = RuntimeBitAssignBox{value: 0xF0}
    box |= 0x0F

    @assert(box.value == 0xFF)
    @assert(box.calls == 1)
}

// Test: ^=
#test
{
    var box = RuntimeBitAssignBox{value: 0xFF}
    box ^= 0x0F

    @assert(box.value == 0xF0)
    @assert(box.calls == 1)
}

// Test: >>=
#test
{
    var box = RuntimeBitAssignBox{value: 256}
    box >>= 4

    @assert(box.value == 16)
    @assert(box.calls == 1)
}

// Test: sequential bitwise assigns
#test
{
    var box = RuntimeBitAssignBox{value: 0x00}
    box |= 0xFF
    box &= 0x0F
    box ^= 0x05

    @assert(box.value == 0x0A)
    @assert(box.calls == 3)
}
