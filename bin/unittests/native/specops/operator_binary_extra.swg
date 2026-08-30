#global private

// ============================================================================
// opBinary: identity and commutativity tests
// ============================================================================

struct RuntimeCommBox
{
    value: s32
}

impl RuntimeCommBox
{
    #[Swag.NoInline]
    mtd(op: Swag.Operator) const opBinary(other: RuntimeCommBox)->RuntimeCommBox
        where op == .Add or op == .Mul
    {
        #static switch op
        {
        case .Add:
            return {value: .value + other.value}

        case .Mul:
            return {value: .value * other.value}

        }
    }

    #[Swag.NoInline]
    mtd const opEquals(other: RuntimeCommBox)->bool
    {
        return .value == other.value
    }
}

// Test: additive identity (a + 0 == a)
#test
{
    var a      = RuntimeCommBox{value: 42}
    var zero   = RuntimeCommBox{value: 0}
    let result = a + zero

    Swag.assert(result.value == 42)
}

// Test: multiplicative identity (a * 1 == a)
#test
{
    var a      = RuntimeCommBox{value: 42}
    var one    = RuntimeCommBox{value: 1}
    let result = a * one

    Swag.assert(result.value == 42)
}

// Test: multiplicative zero (a * 0 == 0)
#test
{
    var a      = RuntimeCommBox{value: 42}
    var zero   = RuntimeCommBox{value: 0}
    let result = a * zero

    Swag.assert(result.value == 0)
}

// Test: commutativity of + (a + b == b + a)
#test
{
    var a = RuntimeCommBox{value: 13}
    var b = RuntimeCommBox{value: 29}

    Swag.assert((a + b) == (b + a))
}

// Test: commutativity of * (a * b == b * a)
#test
{
    var a = RuntimeCommBox{value: 7}
    var b = RuntimeCommBox{value: 11}

    Swag.assert((a * b) == (b * a))
}

// Test: associativity of + ((a+b)+c == a+(b+c))
#test
{
    var a = RuntimeCommBox{value: 3}
    var b = RuntimeCommBox{value: 5}
    var c = RuntimeCommBox{value: 7}

    Swag.assert(((a + b) + c) == (a + (b + c)))
}

// ============================================================================
// opBinary: non-generic subtraction and division
// ============================================================================

struct RuntimeFullArithBox
{
    a: s32
    b: s32
}

impl RuntimeFullArithBox
{
    #[Swag.NoInline]
    mtd(op: Swag.Operator) const opBinary(other: RuntimeFullArithBox)->RuntimeFullArithBox
        where op == .Add or op == .Sub or op == .Mul or op == .Div or op == .Mod
    {
        #static switch op
        {
        case .Add:
            return {a: .a + other.a, b: .b + other.b}

        case .Sub:
            return {a: .a - other.a, b: .b - other.b}

        case .Mul:
            return {a: .a * other.a, b: .b * other.b}

        case .Div:
            return {a: .a / other.a, b: .b / other.b}

        case .Mod:
            return {a: .a % other.a, b: .b % other.b}

        }
    }

    #[Swag.NoInline]
    mtd(op: Swag.Operator) const opBinary(scalar: s32)->RuntimeFullArithBox
        where op == .Add or op == .Sub or op == .Mul or op == .Div or op == .Mod
    {
        #static switch op
        {
        case .Add:
            return {a: .a + scalar, b: .b + scalar}

        case .Sub:
            return {a: .a - scalar, b: .b - scalar}

        case .Mul:
            return {a: .a * scalar, b: .b * scalar}

        case .Div:
            return {a: .a / scalar, b: .b / scalar}

        case .Mod:
            return {a: .a % scalar, b: .b % scalar}

        }
    }
}

// Test: struct - struct
#test
{
    var lhs  = RuntimeFullArithBox{a: 10, b: 20}
    var rhs  = RuntimeFullArithBox{a: 3, b: 7}
    let diff = lhs - rhs

    Swag.assert(diff.a == 7)
    Swag.assert(diff.b == 13)
}

// Test: struct / struct
#test
{
    var lhs  = RuntimeFullArithBox{a: 100, b: 50}
    var rhs  = RuntimeFullArithBox{a: 10, b: 5}
    let quot = lhs / rhs

    Swag.assert(quot.a == 10)
    Swag.assert(quot.b == 10)
}

// Test: struct % struct
#test
{
    var lhs = RuntimeFullArithBox{a: 17, b: 25}
    var rhs = RuntimeFullArithBox{a: 5, b: 7}
    let rem = lhs % rhs

    Swag.assert(rem.a == 2)
    Swag.assert(rem.b == 4)
}

// Test: struct - scalar
#test
{
    var box    = RuntimeFullArithBox{a: 10, b: 20}
    let result = box - 3

    Swag.assert(result.a == 7)
    Swag.assert(result.b == 17)
}

// Test: struct / scalar
#test
{
    var box    = RuntimeFullArithBox{a: 100, b: 200}
    let result = box / 10

    Swag.assert(result.a == 10)
    Swag.assert(result.b == 20)
}

// Test: struct % scalar
#test
{
    var box    = RuntimeFullArithBox{a: 10, b: 17}
    let result = box % 3

    Swag.assert(result.a == 1)
    Swag.assert(result.b == 2)
}

// Test: mixed chaining (a + b - c * d)
#test
{
    var a      = RuntimeFullArithBox{a: 10, b: 10}
    var b      = RuntimeFullArithBox{a: 5, b: 5}
    let result = a + b - a

    Swag.assert(result.a == 5)
    Swag.assert(result.b == 5)
}

// ============================================================================
// opBinaryRight and Commutative: scalar op struct
// ============================================================================

struct RuntimeRightArithBox
{
    a: s32
    b: s32
}

impl RuntimeRightArithBox
{
    #[Swag.NoInline, Swag.Commutative(.Add, .Mul)]
    mtd(op: Swag.Operator) const opBinary(scalar: s32)->RuntimeRightArithBox
        where op == .Add or op == .Mul
    {
        #static switch op
        {
        case .Add:
            return {a: .a + scalar, b: .b + scalar}

        case .Mul:
            return {a: .a * scalar, b: .b * scalar}

        }
    }

    #[Swag.NoInline]
    mtd(op: Swag.Operator) const opBinaryRight(scalar: s32)->RuntimeRightArithBox
        where op == .Sub or op == .Div
    {
        #static switch op
        {
        case .Sub:
            return {a: scalar - .a, b: scalar - .b}

        case .Div:
            return {a: scalar / .a, b: scalar / .b}

        }
    }
}

// Test: scalar * struct uses Commutative opBinary on the right operand
#test
{
    var box    = RuntimeRightArithBox{a: 3, b: 7}
    let result = 4 * box

    Swag.assert(result.a == 12)
    Swag.assert(result.b == 28)
}

// Test: non-commutative scalar - struct keeps the operand order
#test
{
    var box    = RuntimeRightArithBox{a: 3, b: 7}
    let result = 10 - box

    Swag.assert(result.a == 7)
    Swag.assert(result.b == 3)
}
