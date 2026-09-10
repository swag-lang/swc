#global private

// ============================================================================
// Generic bool box with ! unary op
// ============================================================================

struct(T) BoolUnaryBox
{
    value: T
}

impl BoolUnaryBox
{
    func(op: Swag.Operator) opUnary(const me)->BoolUnaryBox'T
        where op == .Not
    {
        return {value: not me.value}
    }
}

// Test: unary ! on BoolUnaryBox'bool (false -> true)
#test
{
    var value: BoolUnaryBox'bool = {value: false}
    let flipped = not value

    Swag.assert(flipped.value)
}

// Test: unary ! on BoolUnaryBox'bool (true -> false)
#test
{
    var value: BoolUnaryBox'bool = {value: true}
    let flipped = not value

    Swag.assert(not flipped.value)
}

// Test: double negation on BoolUnaryBox'bool
#test
{
    var value: BoolUnaryBox'bool = {value: true}
    let double_flip = not (not value)

    Swag.assert(double_flip.value)
}
