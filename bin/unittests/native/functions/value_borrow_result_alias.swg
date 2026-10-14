#global private

// ziglang/zig#4021: the result destination aliases both input arguments.
struct Complex { x, y: f64 }

#[Swag.NoInline]
func multiply(left: Complex, right: Complex)->Complex
{
    return {left.x * right.x - left.y * right.y,
            left.x * right.y + left.y * right.x}
}

#test
{
    let imaginary: Complex = {0, 1}
    var value = imaginary
    value = multiply(value, value)
    Swag.assert(value.x == -1 and value.y == 0)
    value = imaginary
    value = multiply(value, imaginary)
    Swag.assert(value.x == -1 and value.y == 0)
    value = imaginary
    value = multiply(imaginary, value)
    Swag.assert(value.x == -1 and value.y == 0)
}

// ziglang/zig#3696: repeated matrix products with the accumulator as destination.
struct Matrix { a, b, c, d: s64 }

#[Swag.NoInline]
func product(left: Matrix, right: Matrix)->Matrix
{
    return {left.a * right.a + left.b * right.c,
            left.a * right.b + left.b * right.d,
            left.c * right.a + left.d * right.c,
            left.c * right.b + left.d * right.d}
}

#test
{
    let first:  Matrix = {1, 2, 3, 4}
    let second: Matrix = {5, 6, 7, 8}
    let expected       = product(product(first, second), first)
    var value          = first
    value = product(value, second)
    value = product(value, first)
    Swag.assert(value.a == expected.a and value.b == expected.b)
    Swag.assert(value.c == expected.c and value.d == expected.d)
    Swag.assert(value.a == 85 and value.b == 126)
    Swag.assert(value.c == 193 and value.d == 286)
}
