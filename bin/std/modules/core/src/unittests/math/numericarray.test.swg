#global #if #command == Swag.CompilerCommand.Test
#global private
using Swag

func expectNumericArray4(values: const &Math.NumericArray'(s32, 4'u32), expected: #nonull const [..] s32)
{
    @assert(@countof(expected) == 4)
    for i in 4
    {
        @assert(values[i] == expected[i])
    }
}

#test
{
    let seed: [4] s32 = [1, 2, 3, 4]

    var values: Math.NumericArray'(s32, 4'u32)
    values = 7
    expectNumericArray4(values, [7, 7, 7, 7])

    values = seed
    expectNumericArray4(values, seed)

    values.set(10, 20, 30, 40)
    expectNumericArray4(values, [10, 20, 30, 40])

    let created = Math.NumericArray'(s32, 4'u32).from(-1, -2, -3, -4)
    expectNumericArray4(created, [-1, -2, -3, -4])
}

#test
{
    var left: Math.NumericArray'(s32, 4'u32)
    var right: Math.NumericArray'(s32, 4'u32)
    left.set(10, 20, 30, 40)
    right.set(1, 2, 5, 8)

    expectNumericArray4(left + right, [11, 22, 35, 48])
    expectNumericArray4(left - right, [9, 18, 25, 32])
    expectNumericArray4(left * right, [10, 40, 150, 320])
    expectNumericArray4(left / right, [10, 10, 6, 5])

    @assert(left == left)
    @assert(left != right)
}

#test
{
    var values: Math.NumericArray'(s32, 4'u32)
    values = 3

    values += 2
    expectNumericArray4(values, [5, 5, 5, 5])

    values *= 4
    expectNumericArray4(values, [20, 20, 20, 20])

    values -= 5
    expectNumericArray4(values, [15, 15, 15, 15])

    values /= 3
    expectNumericArray4(values, [5, 5, 5, 5])
}

#test
{
    var values: Math.NumericArray'(s32, 4'u32)
    var other:  Math.NumericArray'(s32, 4'u32)

    values.set(10, 20, 30, 40)
    other.set(1, 2, 3, 4)

    values += other
    expectNumericArray4(values, [11, 22, 33, 44])

    values -= other
    expectNumericArray4(values, [10, 20, 30, 40])

    values *= other
    expectNumericArray4(values, [10, 40, 90, 160])

    values /= other
    expectNumericArray4(values, [10, 20, 30, 40])
}

#test
{
    var values: Math.NumericArray'(s32, 4'u32)
    values.set(1, 2, 3, 4)
    values.mulAdd(10, 1)
    expectNumericArray4(values, [11, 21, 31, 41])

    var factor: Math.NumericArray'(s32, 4'u32)
    var add:    Math.NumericArray'(s32, 4'u32)
    values.set(2, 3, 4, 5)
    factor.set(1, 2, 3, 4)
    add.set(10, 20, 30, 40)

    values.mulAdd(factor, add)
    expectNumericArray4(values, [12, 26, 42, 60])
}
