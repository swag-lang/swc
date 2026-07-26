#global export
#global namespace Math

using Swag

struct(T, N: u32) NumericArray
{
    buf: [N] T
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
            #static if op == .Add do
                result.buf[i] = .buf[i] + other.buf[i]
            elif op == .Sub do
                result.buf[i] = .buf[i] - other.buf[i]
            elif op == .Mul do
                result.buf[i] = .buf[i] * other.buf[i]
            elif op == .Div do
                result.buf[i] = .buf[i] / other.buf[i]
            else do
                #error("unsupported binary operation [[" ++ op.symbol() ++ "]]")
        }

        return result
    }

    mtd(op: Swag.Operator) opAssign(value: T)
    {
        for [i] in N
        {
            #static if op == .AddAssign do
                .buf[i] += value
            elif (op == .SubAssign) do
                .buf[i] -= value
            elif (op == .MulAssign) do
                .buf[i] *= value
            elif (op == .DivAssign) do
                .buf[i] /= value
            else do
                #error("unsupported assign operation [[" ++ op.symbol() ++ "]]")
        }
    }

    func(op: Swag.Operator) opAssign(me, value: NumericArray)
    {
        for [i] in N
        {
            #static if op == .AddAssign do
                .buf[i] += value.buf[i]
            elif (op == .SubAssign) do
                .buf[i] -= value.buf[i]
            elif (op == .MulAssign) do
                .buf[i] *= value.buf[i]
            elif (op == .DivAssign) do
                .buf[i] /= value.buf[i]
            else do
                #error("unsupported assign operation [[" ++ op.symbol() ++ "]]")
        }
    }

    #[Safety(.BoundCheck, false), Complete]
    mtd opSet(what: T)
    {
        for [i] in N do
            .buf[i] = what
    }

    #[Safety(.BoundCheck, false), Complete]
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
