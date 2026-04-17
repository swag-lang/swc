#global fileprivate

// ============================================================================
// opBinary: identity and commutativity tests
// ============================================================================

struct RuntimeCommBox
{
    value: s32
}

impl RuntimeCommBox
{
    #[Swag.Overload, Swag.NoInline]
    mtd(op: string) const opBinary(other: const &RuntimeCommBox)->RuntimeCommBox
    {
        #if op == "+" do
            return {value: .value + other.value}
        #elif op == "*" do
            return {value: .value * other.value}
        #else do
            #error("unsupported binary operation [[" ++ op ++ "]]")
    }

    #[Swag.Overload, Swag.NoInline]
    mtd const opEquals(other: const &RuntimeCommBox)->bool
    {
        return .value == other.value
    }
}

// Test: additive identity (a + 0 == a)
#test
{
    var a = RuntimeCommBox{value: 42}
    var zero = RuntimeCommBox{value: 0}
    let result = a + zero

    @assert(result.value == 42)
}

// Test: multiplicative identity (a * 1 == a)
#test
{
    var a = RuntimeCommBox{value: 42}
    var one = RuntimeCommBox{value: 1}
    let result = a * one

    @assert(result.value == 42)
}

// Test: multiplicative zero (a * 0 == 0)
#test
{
    var a = RuntimeCommBox{value: 42}
    var zero = RuntimeCommBox{value: 0}
    let result = a * zero

    @assert(result.value == 0)
}

// Test: commutativity of + (a + b == b + a)
#test
{
    var a = RuntimeCommBox{value: 13}
    var b = RuntimeCommBox{value: 29}

    @assert((a + b) == (b + a))
}

// Test: commutativity of * (a * b == b * a)
#test
{
    var a = RuntimeCommBox{value: 7}
    var b = RuntimeCommBox{value: 11}

    @assert((a * b) == (b * a))
}

// Test: associativity of + ((a+b)+c == a+(b+c))
#test
{
    var a = RuntimeCommBox{value: 3}
    var b = RuntimeCommBox{value: 5}
    var c = RuntimeCommBox{value: 7}

    @assert(((a + b) + c) == (a + (b + c)))
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
    #[Swag.Overload, Swag.NoInline]
    mtd(op: string) const opBinary(other: const &RuntimeFullArithBox)->RuntimeFullArithBox
    {
        #if op == "+" do
            return {a: .a + other.a, b: .b + other.b}
        #elif op == "-" do
            return {a: .a - other.a, b: .b - other.b}
        #elif op == "*" do
            return {a: .a * other.a, b: .b * other.b}
        #elif op == "/" do
            return {a: .a / other.a, b: .b / other.b}
        #elif op == "%" do
            return {a: .a % other.a, b: .b % other.b}
        #else do
            #error("unsupported binary operation [[" ++ op ++ "]]")
    }

    #[Swag.Overload, Swag.NoInline]
    mtd(op: string) const opBinary(scalar: s32)->RuntimeFullArithBox
    {
        #if op == "+" do
            return {a: .a + scalar, b: .b + scalar}
        #elif op == "-" do
            return {a: .a - scalar, b: .b - scalar}
        #elif op == "*" do
            return {a: .a * scalar, b: .b * scalar}
        #elif op == "/" do
            return {a: .a / scalar, b: .b / scalar}
        #elif op == "%" do
            return {a: .a % scalar, b: .b % scalar}
        #else do
            #error("unsupported binary operation [[" ++ op ++ "]]")
    }
}

// Test: struct - struct
#test
{
    var lhs = RuntimeFullArithBox{a: 10, b: 20}
    var rhs = RuntimeFullArithBox{a: 3, b: 7}
    let diff = lhs - rhs

    @assert(diff.a == 7)
    @assert(diff.b == 13)
}

// Test: struct / struct
#test
{
    var lhs = RuntimeFullArithBox{a: 100, b: 50}
    var rhs = RuntimeFullArithBox{a: 10, b: 5}
    let quot = lhs / rhs

    @assert(quot.a == 10)
    @assert(quot.b == 10)
}

// Test: struct % struct
#test
{
    var lhs = RuntimeFullArithBox{a: 17, b: 25}
    var rhs = RuntimeFullArithBox{a: 5, b: 7}
    let rem = lhs % rhs

    @assert(rem.a == 2)
    @assert(rem.b == 4)
}

// Test: struct - scalar
#test
{
    var box = RuntimeFullArithBox{a: 10, b: 20}
    let result = box - 3

    @assert(result.a == 7)
    @assert(result.b == 17)
}

// Test: struct / scalar
#test
{
    var box = RuntimeFullArithBox{a: 100, b: 200}
    let result = box / 10

    @assert(result.a == 10)
    @assert(result.b == 20)
}

// Test: struct % scalar
#test
{
    var box = RuntimeFullArithBox{a: 10, b: 17}
    let result = box % 3

    @assert(result.a == 1)
    @assert(result.b == 2)
}

// Test: mixed chaining (a + b - c * d)
#test
{
    var a = RuntimeFullArithBox{a: 10, b: 10}
    var b = RuntimeFullArithBox{a: 5, b: 5}
    let result = a + b - a

    @assert(result.a == 5)
    @assert(result.b == 5)
}
