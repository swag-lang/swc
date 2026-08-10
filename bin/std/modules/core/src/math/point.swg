#global public
#global namespace Math

// A simple 2D point struct with X and Y coordinates.
// Contains x and y components as 32-bit floating point values for representing positions in 2D space.
#[Serialization.Final]
struct Point
{
    x: f32     // X coordinate of the point
    y: f32     // Y coordinate of the point
}

impl Point
{
    const Zero = Point{0, 0}     // Point at origin (0, 0)
    const One  = Point{1, 1}     // Point with both coordinates set to one (1, 1)

    // Set both coordinates to the same scalar value.
    // This allows assignment like 'point = 5.0' to set both coordinates to 5.0.
    #[Swag.FullInit]
    mtd opSet(value: f32)
    {
        .x, .y = value
    }

    // Compound assignment operators for point-point operations (+=, -=, *=, /=).
    // Performs component-wise operations with another point.
    mtd(op: Swag.Operator) opAssign(other: Point)
        where op == .AddAssign or op == .SubAssign or op == .MulAssign or op == .DivAssign
    {
        #static switch op
        {
        case .AddAssign:
            .x += other.x
            .y += other.y

        case .SubAssign:
            .x -= other.x
            .y -= other.y

        case .MulAssign:
            .x *= other.x
            .y *= other.y

        case .DivAssign:
            .x /= other.x
            .y /= other.y
        }
    }

    // Compound assignment operators for point-scalar operations (+=, -=, *=, /=).
    // Applies the scalar 'value' to both coordinates of the point.
    mtd(op: Swag.Operator) opAssign(value: f32)
        where op == .AddAssign or op == .SubAssign or op == .MulAssign or op == .DivAssign
    {
        #static switch op
        {
        case .AddAssign:
            .x += value
            .y += value

        case .SubAssign:
            .x -= value
            .y -= value

        case .MulAssign:
            .x *= value
            .y *= value

        case .DivAssign:
            .x /= value
            .y /= value
        }
    }

    // Binary operators for point-point operations (+, -, *, /).
    // Performs component-wise operations between two points and returns the result.
    mtd(op: Swag.Operator) const opBinary(other: Point)->Point
        where op == .Add or op == .Sub or op == .Mul or op == .Div
    {
        #static switch op
        {
        case .Add: return Point{.x + other.x, .y + other.y}
        case .Sub: return Point{.x - other.x, .y - other.y}
        case .Mul: return Point{.x * other.x, .y * other.y}
        case .Div: return Point{.x / other.x, .y / other.y}
        }
    }

    // Binary operators for point-scalar operations (+, -, *, /).
    // Applies the scalar 'value' to both coordinates and returns the result.
    mtd(op: Swag.Operator) const opBinary(value: f32)->Point
        where op == .Add or op == .Sub or op == .Mul or op == .Div
    {
        #static switch op
        {
        case .Add: return Point{.x + value, .y + value}
        case .Sub: return Point{.x - value, .y - value}
        case .Mul: return Point{.x * value, .y * value}
        case .Div: return Point{.x / value, .y / value}
        }
    }

    // Apply unary operations to the point.
    // Currently supports negation (-) to return a point with both coordinates negated.
    mtd(op: Swag.Operator) const opUnary()->Point
        where op == .Neg
    {
        var result: retval
        result.x = -.x
        result.y = -.y
        return result
    }

    // Set both coordinates to zero.
    // Equivalent to assigning the 'Zero' constant but modifies the current instance.
    mtd clear()
    {
        .x, .y = 0
    }

    // Returns true if this point is exactly at the origin.
    // Performs exact floating-point comparison, which may not work well with computed values.
    mtd const isZero()->bool
    {
        return .x == 0 and .y == 0
    }

    // Returns true if this point is at the origin within an epsilon tolerance.
    // Uses 'eps' parameter to handle floating-point precision issues.
    mtd const isZeroEpsilon(eps = ConstF32.Epsilon)->bool
    {
        return isZeroEpsilon(.x, eps) and isZeroEpsilon(.y, eps)
    }

    // Returns true if this point is equal to 'other' within an epsilon tolerance.
    // Compares each coordinate separately using the specified 'eps' tolerance.
    mtd const isEqualEpsilon(other: Point, eps = ConstF32.Epsilon)->bool
    {
        return Math.isEqualEpsilon(.x, other.x, eps) and Math.isEqualEpsilon(.y, other.y, eps)
    }

    // Offset both coordinates by the same scalar value.
    // Adds 'value' to both x and y coordinates of this point.
    mtd offset(value: f32)
    {
        .x, .y += value
    }

    // Offset this point by separate x and y values.
    // Adds the specified 'x' and 'y' offsets to the corresponding coordinates.
    func offset(me, x, y: f32)
    {
        .x += x
        .y += y
    }

    // Round both coordinates to the nearest integer values.
    // Applies 'Math.round' function to both x and y coordinates in-place.
    mtd round()
    {
        .x = Math.round(.x)
        .y = Math.round(.y)
    }

    // Truncate both coordinates to integer values.
    // Applies 'Math.trunc' function to both x and y coordinates, removing fractional parts.
    mtd trunc()
    {
        .x = Math.trunc(.x)
        .y = Math.trunc(.y)
    }

    // Round both coordinates up to the next integer values.
    // Applies 'Math.ceil' function to both x and y coordinates in-place.
    mtd ceil()
    {
        .x = Math.ceil(.x)
        .y = Math.ceil(.y)
    }
}
