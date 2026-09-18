#global public
#global namespace Math

// Stores a position in the plane as two `f32` coordinates.
//
// [[Core.Math.Rectangle]] reports its corners and its size with this type. Use
// [[Core.Math.Vector2]] for the vector operations a point does not offer.
#[Serialization.Final]
struct Point
{
    public
    {
        x: f32     // Horizontal coordinate
        y: f32     // Vertical coordinate
    }
}

impl Point
{
    const Zero = Point{0, 0}     // Point at origin (0, 0)
    const One  = Point{1, 1}     // Point with both coordinates set to one (1, 1)

    // Sets both coordinates to `value`.
    //
    // This is what lets a scalar initialize or assign a point, as in `point = 5.0`.
    mtd opSet(value: f32)
    {
        .x, .y = value
    }

    // Applies `+=`, `-=`, `*=`, or `/=` coordinate by coordinate with `other`.
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

    // Applies `+=`, `-=`, `*=`, or `/=` with the scalar `value` to both coordinates.
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

    // Returns the coordinate-wise sum, difference, product, or quotient with `other`.
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

    // Returns this point with `+`, `-`, `*`, or `/` applied to both coordinates and the scalar `value`.
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

    // Returns this point with both coordinates negated.
    mtd(op: Swag.Operator) const opUnary()->Point
        where op == .Neg
    {
        var result: retval
        result.x = -.x
        result.y = -.y
        return result
    }

    // Sets both coordinates to zero.
    mtd clear()
    {
        .x, .y = 0
    }

    // Returns whether both coordinates are exactly zero.
    //
    // Use [[Core.Math.Point.isZeroEpsilon]] for computed values.
    mtd const isZero()->bool => .x == 0 and .y == 0

    // Returns whether both coordinates are closer to zero than `eps`.
    mtd const isZeroEpsilon(eps = ConstF32.Epsilon)->bool => isZeroEpsilon(.x, eps) and isZeroEpsilon(.y, eps)

    // Returns whether each coordinate is closer than `eps` to the matching coordinate of `other`.
    mtd const isEqualEpsilon(other: Point, eps = ConstF32.Epsilon)->bool => Math.isEqualEpsilon(.x, other.x, eps) and Math.isEqualEpsilon(.y, other.y, eps)

    // Adds `value` to both coordinates.
    mtd offset(value: f32)
    {
        .x, .y += value
    }

    // Adds `x` to the horizontal coordinate and `y` to the vertical one.
    mtd offset(x, y: f32)
    {
        .x += x
        .y += y
    }

    // Rounds both coordinates to the nearest integer values in place.
    //
    // A coordinate halfway between two integers rounds away from zero.
    mtd round()
    {
        .x = Math.round(.x)
        .y = Math.round(.y)
    }

    // Rounds both coordinates toward zero in place.
    mtd trunc()
    {
        .x = Math.trunc(.x)
        .y = Math.trunc(.y)
    }

    // Rounds both coordinates up to integer values in place.
    mtd ceil()
    {
        .x = Math.ceil(.x)
        .y = Math.ceil(.y)
    }
}
