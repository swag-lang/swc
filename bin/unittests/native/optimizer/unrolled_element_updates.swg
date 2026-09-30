#global private
using Swag

// An element-wise update by one scalar, unrolled. Every copy reads the same
// operand: a copy that takes the operand's register for its own result leaves
// the following copies a product instead of the factor.

struct Four
{
    values: [4] s32
}

impl Four
{
    #[Swag.Optimize(true), Swag.NoInline]
    mtd add(value: s32)
    {
        for i in 4 do
            .values[i] += value
    }

    #[Swag.Optimize(true), Swag.NoInline]
    mtd subtract(value: s32)
    {
        for i in 4 do
            .values[i] -= value
    }

    #[Swag.Optimize(true), Swag.NoInline]
    mtd multiply(value: s32)
    {
        for i in 4 do
            .values[i] *= value
    }

    #[Swag.Optimize(true), Swag.NoInline]
    mtd divide(value: s32)
    {
        for i in 4 do
            .values[i] /= value
    }

    // The factor is read again after the last element.
    #[Swag.Optimize(true), Swag.NoInline]
    mtd multiplyAndReturn(value: s64)->s64
    {
        var wide: [3] s64 = [2, 3, 5]
        for i in 3 do
            wide[i] *= value
        return wide[0] + wide[1] + wide[2] + value
    }
}

#test
{
    var four = Four{[3, 4, 5, 6]}
    four.add(2)
    Swag.assert(four.values == [5, 6, 7, 8])
    four.multiply(4)
    Swag.assert(four.values == [20, 24, 28, 32])
    four.subtract(5)
    Swag.assert(four.values == [15, 19, 23, 27])
    four.divide(3)
    Swag.assert(four.values == [5, 6, 7, 9])
    Swag.assert(four.multiplyAndReturn(7) == 14 + 21 + 35 + 7)
}
