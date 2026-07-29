#global export
#global namespace Math

using Swag

// Represents numeric array.
struct(T, N: u32) NumericArray
{
    buf: [N] T // Buf associated with this value.
}

impl NumericArray
{
    #[Inline]
    mtd const opIndex(idx: u64)->T
    {
        return .buf[idx]
    }

    mtd const opEquals(other: NumericArray)->bool
    {
        for [i] in N
        {
            if .buf[i] != other.buf[i] do
                return false
        }

        return true
    }

    mtd(op: Swag.Operator) const opBinary(other: const &NumericArray)->NumericArray
    {
        var result: retval
        for [i] in N
        {
            #static switch op
            {
            case .Add: result.buf[i] = .buf[i] + other.buf[i]
            case .Sub: result.buf[i] = .buf[i] - other.buf[i]
            case .Mul: result.buf[i] = .buf[i] * other.buf[i]
            case .Div: result.buf[i] = .buf[i] / other.buf[i]
            default:   #error("unsupported binary operation [[" ++ op.symbol() ++ "]]")
            }
        }

        return result
    }

    mtd(op: Swag.Operator) opAssign(value: T)
    {
        for [i] in N
        {
            #static switch op
            {
            case .AddAssign: .buf[i] += value
            case .SubAssign: .buf[i] -= value
            case .MulAssign: .buf[i] *= value
            case .DivAssign: .buf[i] /= value
            default:         #error("unsupported assign operation [[" ++ op.symbol() ++ "]]")
            }
        }
    }

    func(op: Swag.Operator) opAssign(me, value: NumericArray)
    {
        for [i] in N
        {
            #static switch op
            {
            case .AddAssign: .buf[i] += value.buf[i]
            case .SubAssign: .buf[i] -= value.buf[i]
            case .MulAssign: .buf[i] *= value.buf[i]
            case .DivAssign: .buf[i] /= value.buf[i]
            default:         #error("unsupported assign operation [[" ++ op.symbol() ++ "]]")
            }
        }
    }

    #[Safety(.BoundCheck, false), FullInit]
    mtd opSet(what: T)
    {
        for [i] in N do
            .buf[i] = what
    }

    #[Safety(.BoundCheck, false), FullInit]
    mtd opSet(what: const [..] T)
    {
        Debug.assert(@countof(what) == N)
        for [i] in N do
            .buf[i] = what[i]
    }

    #[Safety(.BoundCheck, false)]
    func from(values: T...)->NumericArray
    {
        Debug.assert(@countof(values) == N)
        var result: retval
        for N do
            result.buf[@index] = values[@index]
        return result
    }

    // Set all values
    #[Safety(.BoundCheck, false)]
    mtd set(values: T...)
    {
        Debug.assert(@countof(values) == N)
        for [i] in N do
            .buf[i] = values[i]
    }

    // Multiply & add
    #[Safety(.BoundCheck, false)]
    mtd mulAdd(value1, value2: T)
    {
        for [i] in N do
            .buf[i] = (.buf[i] * value1) + value2
    }

    // Multiply & Add
    #[Safety(.BoundCheck, false)]
    mtd mulAdd(value1, value2: NumericArray)
    {
        for [i] in N do
            .buf[i] = (.buf[i] * value1[i]) + value2.buf[i]
    }
}
