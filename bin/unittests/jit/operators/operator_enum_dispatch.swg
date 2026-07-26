#global private

// Operator hooks receive a 'Swag.Operator' value, not a string. One hook covers a whole
// family, each spelling has its own member, and a misspelled member cannot compile.

struct Vec
{
    x, y: s32
}

impl Vec
{
    mtd(op: Swag.Operator) const opBinary(other: Vec)->Vec
    {
        #if op == .Add do
            return Vec{.x + other.x, .y + other.y}
        #elif op == .Sub do
            return Vec{.x - other.x, .y - other.y}
        #elif op == .Mul do
            return Vec{.x * other.x, .y * other.y}
        #elif op == .BitXor do
            return Vec{.x ^ other.x, .y ^ other.y}
        #elif op == .Shl do
            return Vec{.x << other.x, .y << other.y}
        #else do
            #error("unsupported binary operation [[" ++ op.symbol() ++ "]]")
    }

    // Unary '-' arrives as 'Neg' and unary '+' as 'Pos', so neither collides with the
    // binary 'Sub' and 'Add' handled above.
    mtd(op: Swag.Operator) const opUnary()->Vec
    {
        #if op == .Neg do
            return Vec{-.x, -.y}
        #elif op == .Pos do
            return Vec{.x, .y}
        #elif op == .BitNot do
            return Vec{~.x, ~.y}
        #else do
            #error("unsupported unary operation [[" ++ op.symbol() ++ "]]")
    }

    mtd(op: Swag.Operator) opAssign(other: Vec)
    {
        #if op == .AddAssign
        {
            .x += other.x
            .y += other.y
        }
        #elif op == .SubAssign
        {
            .x -= other.x
            .y -= other.y
        }
        #elif op == .ShrAssign
        {
            .x >>= other.x
            .y >>= other.y
        }
        #else do
            #error("unsupported assign operation [[" ++ op.symbol() ++ "]]")
    }
}

#test
{
    let a = Vec{6, 8}
    let b = Vec{2, 3}

    @assert((a + b).x == 8 and (a + b).y == 11)
    @assert((a - b).x == 4 and (a - b).y == 5)
    @assert((a * b).x == 12 and (a * b).y == 24)
    @assert((a ^ b).x == 4)
    @assert((a << b).x == 24)
}

// The same distinction holds at compile time.
#test
{
    const A = #run
    {
        let a = Vec{6, 8}
        let b = Vec{2, 3}
        return (a + b).x
    }

    #assert(A == 8)
}

#test
{
    let a = Vec{6, 8}

    // Unary minus is 'Neg', not 'Sub'.
    @assert((-a).x == -6 and (-a).y == -8)
    @assert((+a).x == 6)
    @assert((~a).x == ~6)
}

#test
{
    var v = Vec{10, 20}

    v += Vec{1, 2}
    @assert(v.x == 11 and v.y == 22)

    v -= Vec{1, 2}
    @assert(v.x == 10 and v.y == 20)

    v >>= Vec{1, 1}
    @assert(v.x == 5 and v.y == 10)
}

// 'op.symbol()' gives back the source spelling, and it folds at compile time.
#test
{
    #assert(Swag.Operator.Add.symbol() == "+")
    #assert(Swag.Operator.Sub.symbol() == "-")
    #assert(Swag.Operator.Neg.symbol() == "-")
    #assert(Swag.Operator.Pos.symbol() == "+")
    #assert(Swag.Operator.AddAssign.symbol() == "+=")
    #assert(Swag.Operator.ShlAssign.symbol() == "<<=")
    #assert(Swag.Operator.BitNot.symbol() == "~")
}

// A commutative overload restricted to selected operators, using the enum shorthand for
// every argument of the variadic attribute.
struct Scaled
{
    value: s32
}

impl Scaled
{
    #[Swag.Commutative(.Add, .Mul)]
    mtd(op: Swag.Operator) const opBinary(scalar: s32)->Scaled
    {
        #if op == .Add do
            return Scaled{.value + scalar}
        #elif op == .Mul do
            return Scaled{.value * scalar}
        #elif op == .Sub do
            return Scaled{.value - scalar}
        #else do
            #error("unsupported binary operation [[" ++ op.symbol() ++ "]]")
    }
}

#test
{
    let s = Scaled{10}

    // Receiver on the left works for every implemented operator.
    @assert((s + 5).value == 15)
    @assert((s * 5).value == 50)
    @assert((s - 5).value == 5)

    // Receiver on the right only for the operators listed in 'Commutative'.
    @assert((5 + s).value == 15)
    @assert((5 * s).value == 50)
}
