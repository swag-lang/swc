#global private

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
    mtd(op: Swag.Operator) opAssign(rhs: s32)
        where op == .AddAssign or op == .SubAssign or op == .MulAssign or op == .DivAssign or op == .ModAssign
    {
        .calls += 1
        #static switch op
        {
        case .AddAssign:
            .value += rhs

        case .SubAssign:
            .value -= rhs

        case .MulAssign:
            .value *= rhs

        case .DivAssign:
            .value /= rhs

        case .ModAssign:
            .value %= rhs

        }
    }
}

// Test: -=
#test
{
    var box = RuntimeArithAssignBox{value: 100}
    box -= 37

    Swag.assert(box.value == 63)
    Swag.assert(box.calls == 1)
}

// Test: /=
#test
{
    var box = RuntimeArithAssignBox{value: 100}
    box /= 4

    Swag.assert(box.value == 25)
    Swag.assert(box.calls == 1)
}

// Test: %=
#test
{
    var box = RuntimeArithAssignBox{value: 17}
    box %= 5

    Swag.assert(box.value == 2)
    Swag.assert(box.calls == 1)
}

// Test: sequential chained assigns
#test
{
    var box = RuntimeArithAssignBox{value: 10}
    box += 5
    box *= 3
    box -= 15

    Swag.assert(box.value == 30)
    Swag.assert(box.calls == 3)
}

// Test: -= to negative
#test
{
    var box = RuntimeArithAssignBox{value: 3}
    box -= 10

    Swag.assert(box.value == -7)
    Swag.assert(box.calls == 1)
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
    mtd(op: Swag.Operator) opAssign(rhs: u32)
        where op == .BitAndAssign or op == .BitOrAssign or op == .BitXorAssign or op == .ShlAssign or op == .ShrAssign
    {
        .calls += 1
        #static switch op
        {
        case .BitAndAssign:
            .value &= rhs

        case .BitOrAssign:
            .value |= rhs

        case .BitXorAssign:
            .value ^= rhs

        case .ShlAssign:
            .value <<= rhs

        case .ShrAssign:
            .value >>= rhs

        }
    }
}

// Test: &=
#test
{
    var box = RuntimeBitAssignBox{value: 0xFF}
    box &= 0x0F

    Swag.assert(box.value == 0x0F)
    Swag.assert(box.calls == 1)
}

// Test: |=
#test
{
    var box = RuntimeBitAssignBox{value: 0xF0}
    box |= 0x0F

    Swag.assert(box.value == 0xFF)
    Swag.assert(box.calls == 1)
}

// Test: ^=
#test
{
    var box = RuntimeBitAssignBox{value: 0xFF}
    box ^= 0x0F

    Swag.assert(box.value == 0xF0)
    Swag.assert(box.calls == 1)
}

// Test: >>=
#test
{
    var box = RuntimeBitAssignBox{value: 256}
    box >>= 4

    Swag.assert(box.value == 16)
    Swag.assert(box.calls == 1)
}

// Test: sequential bitwise assigns
#test
{
    var box = RuntimeBitAssignBox{value: 0x00}
    box |= 0xFF
    box &= 0x0F
    box ^= 0x05

    Swag.assert(box.value == 0x0A)
    Swag.assert(box.calls == 3)
}
