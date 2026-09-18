#global export
#global namespace Math

using Swag

// Stores `N` numeric components of type `T`, with arithmetic applied component by component.
struct(T, N: u32) NumericArray
{
    public buf: [N] T     // Components in index order
}

impl NumericArray
{
    // Returns the component at the zero-based index, which must be less than `N`.
    #[Inline]
    mtd const opIndex(idx: u64)->T => .buf[idx]

    // Returns whether every component equals the matching component of `other`.
    mtd const opEquals(other: NumericArray)->bool
    {
        for i in N
        {
            if .buf[i] != other.buf[i] do
                return false
        }

        return true
    }

    // Returns the component-wise sum, difference, product, or quotient with `other`.
    mtd(op: Swag.Operator) const opBinary(other: NumericArray)->NumericArray
        where op == .Add or op == .Sub or op == .Mul or op == .Div
    {
        var result: retval
        for i in N
        {
            #static switch op
            {
            case .Add: result.buf[i] = .buf[i] + other.buf[i]
            case .Sub: result.buf[i] = .buf[i] - other.buf[i]
            case .Mul: result.buf[i] = .buf[i] * other.buf[i]
            case .Div: result.buf[i] = .buf[i] / other.buf[i]
            }
        }

        return result
    }

    // Applies `+=`, `-=`, `*=`, or `/=` with the scalar `value` to every component.
    mtd(op: Swag.Operator) opAssign(value: T)
        where op == .AddAssign or op == .SubAssign or op == .MulAssign or op == .DivAssign
    {
        for i in N
        {
            #static switch op
            {
            case .AddAssign: .buf[i] += value
            case .SubAssign: .buf[i] -= value
            case .MulAssign: .buf[i] *= value
            case .DivAssign: .buf[i] /= value
            }
        }
    }

    // Applies `+=`, `-=`, `*=`, or `/=` component by component with `value`.
    func(op: Swag.Operator) opAssign(me, value: NumericArray)
        where op == .AddAssign or op == .SubAssign or op == .MulAssign or op == .DivAssign
    {
        for i in N
        {
            #static switch op
            {
            case .AddAssign: .buf[i] += value.buf[i]
            case .SubAssign: .buf[i] -= value.buf[i]
            case .MulAssign: .buf[i] *= value.buf[i]
            case .DivAssign: .buf[i] /= value.buf[i]
            }
        }
    }

    // Sets every component to `what`.
    #[Safety(.BoundCheck, false), FullInit]
    mtd opSet(what: T)
    {
        for i in N do
            .buf[i] = what
    }

    // Copies the components from `what`, which must hold exactly `N` values.
    #[Safety(.BoundCheck, false), FullInit]
    mtd opSet(what: const [..] T)
    {
        Swag.assert(what.count == N)
        for i in N do
            .buf[i] = what[i]
    }

    // Creates an array from exactly `N` component values.
    #[Safety(.BoundCheck, false)]
    func from(values: T...)->NumericArray
    {
        Swag.assert(values.count == N)
        var result: retval
        for index in N do
            result.buf[index] = values[index]
        return result
    }

    // Sets the components from `values`, which must hold exactly `N` values.
    #[Safety(.BoundCheck, false)]
    mtd set(values: T...)
    {
        Swag.assert(values.count == N)
        for i in N do
            .buf[i] = values[i]
    }

    // Multiplies every component by `value1`, then adds `value2`, in place.
    #[Safety(.BoundCheck, false)]
    mtd mulAdd(value1, value2: T)
    {
        for i in N do
            .buf[i] = (.buf[i] * value1) + value2
    }

    // Multiplies every component by the matching component of `value1`, then adds the matching component of `value2`, in place.
    #[Safety(.BoundCheck, false)]
    mtd mulAdd(value1, value2: NumericArray)
    {
        for i in N do
            .buf[i] = (.buf[i] * value1.buf[i]) + value2.buf[i]
    }
}
